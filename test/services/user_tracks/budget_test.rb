require 'test_helper'

class UserTracks::BudgetTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks(daily_budget_usd: 1.0)
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  test "sums today's estimates, deleted and failed tracks included, against the daily budget" do
    create_user_track(@user, generation: { 'costUsd' => 0.4 })
    UserTracks::Removal.call(create_user_track(@user, generation: { 'costUsd' => 0.3 }))
    create_user_track(@user, status: 'failed', generation: { 'costUsd' => 0.2 })
    create_user_track(@user, created_at: 2.days.ago, generation: { 'costUsd' => 5 })
    create_user_track(@user)

    assert_in_delta 0.9, UserTracks::Budget.spent_today, 1e-9
    assert UserTracks::Budget.allow?(0.1)
    refute UserTracks::Budget.allow?(0.11)
  end

  test 'a track started yesterday but submitted again today counts today' do
    create_user_track(@user, created_at: 1.day.ago, submitted_at: Time.current, generation: { 'costUsd' => 0.95 })
    refute UserTracks::Budget.allow?(0.1)
  end
end
