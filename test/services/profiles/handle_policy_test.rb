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

  test 'a profile row without a handle can set one freely' do
    profile = create(:user_profile, handle: nil)
    assert_equal :ok, check('fresh', user: profile.user)
  end
end
