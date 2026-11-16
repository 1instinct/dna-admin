require 'test_helper'

class UserTracks::BudgetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  # The SQL a block runs, in order.
  def statements
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
    sql
  end

  def budget_lock?(statement)
    statement.include?('pg_advisory_xact_lock') && statement.include?("#{UserTracks::Budget::LOCK[0]}, 0")
  end

  def checked_under_lock?(sql)
    lock = sql.index { |s| budget_lock?(s) }
    sum = sql.index { |s| s.include?("generation->>'costUsd'") }
    lock && sum && lock < sum
  end

  test 'Start checks and reserves under the lock every user shares' do
    track = Spree::UserTrack.new(user: @user, request: track_request)
    sql = statements { UserTracks::Start.call(track) }
    assert checked_under_lock?(sql), sql.grep(/advisory|costUsd/).inspect
    assert track.persisted?
  end

  test 'a regeneration submit checks and reserves under the same lock' do
    track = create_user_track(@user, status: 'queued',
                                     generation: { 'requestId' => nil, 'attempts' => 1, 'costUsd' => 0.0144 })
    stub_request(:post, /queue.fal.run/).to_return(status: 200, body: { request_id: 'req-2' }.to_json)
    sql = statements { UserTracks::SubmitJob.perform_now(track.id) }
    assert checked_under_lock?(sql), sql.grep(/advisory|costUsd/).inspect
    assert_in_delta 0.0288, track.reload.generation['costUsd'], 1e-9
  end

  test 'a track started yesterday but submitted again today counts today' do
    create_user_track(@user, created_at: 1.day.ago, submitted_at: Time.current, generation: { 'costUsd' => 0.95 })
    refute UserTracks::Budget.allow?(0.1)
  end
end
