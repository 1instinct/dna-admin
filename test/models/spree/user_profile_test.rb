require 'test_helper'

class Spree::UserProfileTest < ActiveSupport::TestCase
  test 'handle is stored stripped and lowercase' do
    profile = create(:user_profile, handle: '  NoVa ')
    assert_equal 'nova', profile.reload.handle
  end

  test 'blank handle is stored as nil (no public profile yet)' do
    profile = create(:user_profile, handle: '')
    assert_nil profile.handle
  end

  test 'handle format errors' do
    with_moderation_lists do
      %w[ab no__va _nova nova_ 12345 no-va].each do |h|
        profile = build(:user_profile, handle: h)
        refute profile.valid?, h
        assert profile.errors[:handle].any?, h
      end
    end
  end

  test 'handle is unique case-insensitively' do
    create(:user_profile, handle: 'nova')
    profile = build(:user_profile, handle: 'NOVA')
    refute profile.valid?
    assert_includes profile.errors[:handle], 'is taken'
  end

  test 'database enforces case-insensitive uniqueness too' do
    create(:user_profile, handle: 'nova')
    other = create(:user_profile, handle: 'other')
    assert_raises(ActiveRecord::RecordNotUnique) { other.update_column(:handle, 'NOVA') }
  end

  test 'reserved and blocked handles are refused' do
    with_moderation_lists do
      reserved = build(:user_profile, handle: 'admin')
      refute reserved.valid?
      assert_includes reserved.errors[:handle], 'is reserved'

      blocked = build(:user_profile, handle: 'thebadword')
      refute blocked.valid?
      assert_includes blocked.errors[:handle], "isn't allowed"
    end
  end

  test 'an admin owner may save a reserved handle; a member may not' do
    with_moderation_lists do
      Profiles.config.reserved_prefixes = %w[acme]
      admin = make_admin(create(:user))
      assert create(:user_profile, user: admin, handle: 'acme').persisted?

      member = build(:user_profile, handle: 'acme_two')
      refute member.valid?
      assert_includes member.errors[:handle], 'is reserved'

      other_admin = build(:user_profile, user: make_admin(create(:user)), handle: 'ACME')
      refute other_admin.valid?
      assert_includes other_admin.errors[:handle], 'is taken'
    end
  end

  test 'handle cooldown: 14 days after a change, first set free' do
    profile = create(:user_profile, handle: nil)
    profile.update!(handle: 'first')
    assert_nil profile.handle_changed_at
    profile.update!(handle: 'second')
    changed_at = profile.handle_changed_at
    assert changed_at.present?

    refute profile.update(handle: 'third')
    assert profile.errors[:handle].first.include?('14 days')

    profile.reload.update_column(:handle_changed_at, 14.days.ago - 1.minute)
    assert profile.update(handle: 'third')
  end

  test 'a handle cannot be removed once set' do
    profile = create(:user_profile, handle: 'nova')
    refute profile.update(handle: '')
    assert profile.errors[:handle].any?
  end

  test 'one profile per user' do
    profile = create(:user_profile)
    dup = build(:user_profile, user: profile.user, handle: 'another')
    refute dup.valid?
  end

  test 'name, bio and website limits' do
    profile = build(:user_profile, name: 'n' * 41)
    refute profile.valid?
    assert profile.errors[:name].any?

    profile = build(:user_profile, bio: 'b' * 281)
    refute profile.valid?
    assert profile.errors[:bio].any?

    assert build(:user_profile, name: 'n' * 40, bio: 'b' * 280).valid?
  end

  test 'website must be an http(s) URL of at most 200 chars' do
    assert build(:user_profile, website: 'https://example.com/me').valid?
    assert build(:user_profile, website: 'http://example.com').valid?
    ['ftp://example.com', 'javascript:alert(1)', 'example.com', 'https://', "https://#{'a' * 200}.com"].each do |url|
      profile = build(:user_profile, website: url)
      refute profile.valid?, url
      assert profile.errors[:website].any?, url
    end
  end

  test 'blank name, bio and website are stored as nil' do
    profile = create(:user_profile, name: ' ', bio: '', website: '  ')
    assert_nil profile.name
    assert_nil profile.bio
    assert_nil profile.website
  end

  test 'blocked words in name and bio are refused' do
    with_moderation_lists do
      profile = build(:user_profile, name: 'Mr Badword')
      refute profile.valid?
      assert profile.errors[:name].any?

      profile = build(:user_profile, bio: 'all badwords here')
      refute profile.valid?
      assert profile.errors[:bio].any?
    end
  end

  test 'links keys are limited to the configured list' do
    assert build(:user_profile, links: { 'instagram' => 'nova' }).valid?
    profile = build(:user_profile, links: { 'myspace' => 'nova' })
    refute profile.valid?
    assert profile.errors[:links].any?
    profile = build(:user_profile, links: { 'instagram' => 'x' * 101 })
    refute profile.valid?
  end

  test 'visibility is public or private, default public' do
    assert_equal 'public', create(:user_profile).visibility
    assert build(:user_profile, visibility: 'private').valid?
    refute build(:user_profile, visibility: 'followers').valid?
  end

  test 'avatar accepts jpeg, png and webp only' do
    profile = create(:user_profile)
    profile.avatar.attach(io: StringIO.new('GIF89a'), filename: 'a.gif', content_type: 'image/gif')
    refute profile.valid?
    assert profile.errors[:avatar].any?

    profile = create(:user_profile)
    profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    assert profile.valid?
  end

  test 'avatar must be at most 5 MB' do
    profile = create(:user_profile)
    profile.avatar.attach(io: StringIO.new('x' * (5.megabytes + 1)), filename: 'a.jpg', content_type: 'image/jpeg')
    refute profile.valid?
    assert profile.errors[:avatar].any?
  end

  test 'avatar variants are small 128 and large 512 with metadata stripped' do
    profile = create(:user_profile)
    profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    small = profile.avatar_variant(:small)
    large = profile.avatar_variant(:large)
    assert_equal({ resize_to_fill: [128, 128], strip: true }, small.variation.transformations.except(:format))
    assert_equal({ resize_to_fill: [512, 512], strip: true }, large.variation.transformations.except(:format))
    assert_nil profile.avatar_variant(:original)
  end

  test 'lookup by handle is case-insensitive and visible excludes hidden, locked and deleted users' do
    profile = create(:user_profile, handle: 'nova')
    assert_equal profile, Spree::UserProfile.visible.find_by_handle('NoVa')

    profile.update_column(:hidden_at, Time.current)
    assert_nil Spree::UserProfile.visible.find_by_handle('nova')
    profile.update_column(:hidden_at, nil)

    profile.user.update_column(:locked_at, Time.current)
    assert_nil Spree::UserProfile.visible.find_by_handle('nova')
    profile.user.update_column(:locked_at, nil)

    profile.user.update_column(:deleted_at, Time.current)
    assert_nil Spree::UserProfile.visible.find_by_handle('nova')
  end
end
