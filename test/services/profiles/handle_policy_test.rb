require 'test_helper'

class Profiles::HandlePolicyTest < ActiveSupport::TestCase
  def check(handle, user: nil)
    with_moderation_lists { Profiles::HandlePolicy.check(handle, user: user) }
  end

  test 'normalize strips and lowercases' do
    assert_equal 'nova_7', Profiles::HandlePolicy.normalize('  Nova_7 ')
  end

  test 'valid handles' do
    %w[abc nova nova_7 a1b 7up a_b_c x23456789012345678901234567890].each do |h|
      assert_equal :ok, check(h), h
    end
  end

  test 'mixed case is accepted after normalization' do
    assert_equal :ok, check('NoVa')
  end

  test 'format rules' do
    ['ab', 'a' * 31, 'no-va', 'no.va', 'no va', 'nóva', '12345', '000', '_nova', 'nova_', 'no__va', '', nil].each do |h|
      assert_equal :invalid, check(h), h.inspect
    end
  end

  test 'routes that sit next to handles are reserved in the shipped list' do
    Profiles.reset_config!
    %w[handle_available category tag].each { |h| assert_equal :reserved, Profiles::HandlePolicy.check(h, user: nil), h }
  end

  test 'reserved prefixes refuse any handle starting with them' do
    Profiles.config.reserved_prefixes = %w[acme]
    assert_equal :reserved, Profiles::HandlePolicy.check('acme', user: nil)
    assert_equal :reserved, Profiles::HandlePolicy.check('acme_official', user: nil)
    assert_equal :reserved, Profiles::HandlePolicy.check('Acme2', user: nil)
    assert_equal :ok, Profiles::HandlePolicy.check('not_acme', user: nil)
  ensure
    Profiles.reset_config!
  end

  test 'no reserved prefixes ship with the generic list' do
    refute Rails.root.join('config', 'moderation', 'reserved_prefixes.yml').exist?
  end

  test 'refusal needs no database: rules only' do
    with_moderation_lists do
      assert_equal :invalid, Profiles::HandlePolicy.refusal('a__b')
      assert_equal :reserved, Profiles::HandlePolicy.refusal('admin')
      assert_equal :not_allowed, Profiles::HandlePolicy.refusal('xbadwordx')
      assert_nil Profiles::HandlePolicy.refusal('fine_name')
    end
  end

  test 'reserved handles' do
    assert_equal :reserved, check('admin')
    assert_equal :reserved, check('Support')
  end

  test 'blocked terms match anywhere in a handle' do
    assert_equal :not_allowed, check('xbadwordx')
    assert_equal :not_allowed, check('bad_word')
  end

  test 'taken is case-insensitive and ignores the users own profile' do
    owner = create(:user_profile, handle: 'nova')
    assert_equal :taken, check('NOVA', user: create(:user))
    assert_equal :ok, check('nova', user: owner.user)
  end

  test 'first set is free; changes are limited by the cooldown' do
    profile = create(:user_profile, handle: 'first')
    assert_nil profile.handle_changed_at, 'setting the first handle does not start the cooldown'
    assert_equal :ok, check('second', user: profile.user)

    profile.update!(handle: 'second')
    assert profile.handle_changed_at.present?
    assert_equal :cooldown, check('third', user: profile.user)
    assert_equal :ok, check('second', user: profile.user), 'keeping the current handle is fine'

    profile.update_column(:handle_changed_at, 15.days.ago)
    assert_equal :ok, check('third', user: profile.user)
  end

  test 'admins may take reserved handles and reserved-prefix handles' do
    admin = make_admin(create(:user))
    member = create(:user)
    with_moderation_lists do
      Profiles.config.reserved_prefixes = %w[acme]
      %w[admin Support acme acme_hq acme123].each do |h|
        assert_equal :ok, Profiles::HandlePolicy.check(h, user: admin), h
        assert_equal :reserved, Profiles::HandlePolicy.check(h, user: member), h
        assert_equal :reserved, Profiles::HandlePolicy.check(h, user: nil), h
      end
    end
  end

  test 'admins still get the format rules and blocked terms' do
    admin = make_admin(create(:user))
    with_moderation_lists do
      Profiles.config.reserved_prefixes = %w[acme]
      ['ab', 'a' * 31, '12345', '_admin', 'admin_', 'ad__min', 'acme-hq', ''].each do |h|
        assert_equal :invalid, Profiles::HandlePolicy.check(h, user: admin), h.inspect
      end
      assert_equal :not_allowed, Profiles::HandlePolicy.check('xbadwordx', user: admin)
      assert_equal :not_allowed, Profiles::HandlePolicy.check('acme_badword', user: admin)
    end
  end

  test 'admins still cannot take a handle someone else holds, in any case' do
    create(:user_profile, handle: 'nova')
    admin = make_admin(create(:user))
    assert_equal :taken, check('NOVA', user: admin)
  end

  test 'admins are still held to the cooldown' do
    profile = create(:user_profile, user: make_admin(create(:user)), handle: 'first')
    profile.update!(handle: 'second')
    assert_equal :cooldown, check('admin', user: profile.user)
    profile.update_column(:handle_changed_at, 15.days.ago)
    assert_equal :ok, check('admin', user: profile.user)
  end

  test 'other roles do not unlock reserved handles' do
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'feed_author')
    assert_equal :reserved, check('admin', user: user)
  end

  test 'refusal stays strict unless reserved handles are allowed' do
    with_moderation_lists do
      assert_equal :reserved, Profiles::HandlePolicy.refusal('admin')
      assert_nil Profiles::HandlePolicy.refusal('admin', allow_reserved: true)
      assert_equal :invalid, Profiles::HandlePolicy.refusal('a__b', allow_reserved: true)
      assert_equal :not_allowed, Profiles::HandlePolicy.refusal('xbadwordx', allow_reserved: true)
    end
  end

  test 'a profile row without a handle can set one freely' do
    profile = create(:user_profile, handle: nil)
    assert_equal :ok, check('fresh', user: profile.user)
  end
end
