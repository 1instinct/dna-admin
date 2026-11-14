require 'test_helper'

class Spree::CreatorApplicationTest < ActiveSupport::TestCase
  teardown { DigitalAssets.reset_config! }

  test 'one pending application per user' do
    first = create(:creator_application)
    second = build(:creator_application, user: first.user)
    refute second.valid?
    assert_includes second.errors[:base], 'You already have a pending application'

    first.withdraw!
    assert second.valid?
  end

  test 'the database refuses a second pending row' do
    first = create(:creator_application)
    duplicate = build(:creator_application, user: first.user)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test 'withdraw only when pending' do
    application = create(:creator_application)
    application.withdraw!
    assert_equal 'withdrawn', application.reload.status

    assert_raises(Spree::CreatorApplication::NotPending) { application.withdraw! }
  end

  test 'samples accept up to 3 signed_ids' do
    ids = Array.new(3) { |i| digital_blob(DigitalAssetsTestHelper::WAV_BYTES, "demo#{i}.wav").signed_id }
    application = create(:creator_application, sample_upload_signed_ids: ids)
    assert_equal 3, application.reload.samples.count

    four = Array.new(4) { |i| digital_blob(DigitalAssetsTestHelper::WAV_BYTES, "more#{i}.wav").signed_id }
    over = build(:creator_application, sample_upload_signed_ids: four)
    refute over.valid?
    assert_includes over.errors[:samples], 'at most 3 files'
  end

  test 'samples must be known blobs of an allowed upload type' do
    bad = build(:creator_application, sample_upload_signed_ids: ['nope'])
    refute bad.valid?
    assert_includes bad.errors[:samples], 'contain an unknown upload'

    exe = digital_blob('MZ', 'tool.exe', 'application/x-msdownload')
    refused = build(:creator_application, sample_upload_signed_ids: [exe.signed_id])
    refute refused.valid?
    assert_includes refused.errors[:samples], 'tool.exe is not an allowed file type'
  end

  test 'display name, kinds and portfolio links are checked' do
    DigitalAssets.config.kinds = %w[pack preset]
    application = build(:creator_application, display_name: ' ', kinds: %w[pack shader],
                                              portfolio_links: [{ 'label' => 'x', 'url' => 'javascript:alert(1)' }])
    refute application.valid?
    assert application.errors[:display_name].any?
    assert_includes application.errors[:kinds], 'include an unknown kind: shader'
    assert_includes application.errors[:portfolio_links], 'must be http(s) links with a label'
  end

  test 'kinds may not be empty' do
    application = build(:creator_application, kinds: [])
    refute application.valid?
    assert application.errors[:kinds].any?
  end
end
