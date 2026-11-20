require 'test_helper'

class Profiles::RateLimitTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    Profiles.config.rate_limits[:follow] = { limit: 2, window: 1.hour }
  end

  teardown { Profiles.reset_config! }

  test 'allows up to the limit, then refuses' do
    assert Profiles::RateLimit.allow?(@user, :follow)
    assert Profiles::RateLimit.allow?(@user, :follow)
    refute Profiles::RateLimit.allow?(@user, :follow)
    refute Profiles::RateLimit.allow?(@user, :follow)
  end

  test 'a new window starts over' do
    start = Time.current
    2.times { Profiles::RateLimit.allow?(@user, :follow, now: start) }
    refute Profiles::RateLimit.allow?(@user, :follow, now: start + 59.minutes)

    assert Profiles::RateLimit.allow?(@user, :follow, now: start + 61.minutes)
  end

  test 'counts per user and per action' do
    2.times { Profiles::RateLimit.allow?(@user, :follow) }
    assert Profiles::RateLimit.allow?(create(:user), :follow)
    assert Profiles::RateLimit.allow?(@user, :block)
  end

  test 'keeps one row per user and action' do
    5.times { Profiles::RateLimit.allow?(@user, :follow) }
    assert_equal 1, Spree::ProfileRateCounter.where(user_id: @user.id).count
  end

  test 'ships limits for follow, block, handle_available and avatar' do
    Profiles.reset_config!
    %i[follow block handle_available avatar].each do |action|
      rule = Profiles.config.rate_limits.fetch(action)
      assert_operator rule[:limit], :>, 0
      assert_operator rule[:window], :>, 0
    end
  end

  test 'account deletion removes the counters' do
    Profiles::RateLimit.allow?(@user, :follow)
    AccountDeletion.call(@user)
    assert_equal 0, Spree::ProfileRateCounter.where(user_id: @user.id).count
  end
end
