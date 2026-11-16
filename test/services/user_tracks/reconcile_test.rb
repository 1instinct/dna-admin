require 'test_helper'

# UserTracks::Reconcile: overdue tracks are checked with fal when their owner lists tracks, so
# tracks finish without a worker or a scheduler and survive dyno restarts.
class UserTracks::ReconcileTest < ActiveJob::TestCase
  setup do
    setup_user_tracks
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  test 'a generating track 5 minutes old that fal finished is finalised' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub_fal_status('req-1', 'COMPLETED')
    UserTracks::Reconcile.call(@user)
    assert_enqueued_with(job: UserTracks::FinalizeJob, args: [track.id])
    assert track.reload.checked_at
  end

  test 'one fal failed is failed and refunded' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub_fal_status('req-1', 'COMPLETED', error: 'boom')
    UserTracks::Reconcile.call(@user)
    track.reload
    assert_equal 'failed', track.status
    assert track.credit_refunded_at
  end

  test 'young tracks, other users\' tracks and deleted tracks are not checked' do
    generating_track(@user, submitted_at: 1.minute.ago)
    generating_track(create(:user), submitted_at: 10.minutes.ago)
    UserTracks::Removal.call(generating_track(@user, submitted_at: 10.minutes.ago))
    UserTracks::Reconcile.call(@user)
    assert_not_requested :any, /fal/
  end

  test 'still running: checked at most every so often, and given up on past the limit' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub = stub_fal_status('req-1', 'IN_PROGRESS')
    UserTracks::Reconcile.call(@user)
    UserTracks::Reconcile.call(@user)
    assert_requested stub, times: 1
    assert_equal 'generating', track.reload.status

    track.update_columns(submitted_at: 25.minutes.ago, checked_at: nil)
    UserTracks::Reconcile.call(@user)
    track.reload
    assert_equal 'failed', track.status
    assert_equal 'timeout', track.generation['failure']
    assert track.credit_refunded_at
  end

  test 'fal unreachable changes nothing' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub_request(:get, "#{FAL_QUEUE}/requests/req-1/status").to_timeout
    UserTracks::Reconcile.call(@user)
    assert_equal 'generating', track.reload.status
    assert_no_enqueued_jobs
  end

  test 'a finalise lost to a restart is picked up again' do
    track = generating_track(@user, submitted_at: 15.minutes.ago)
    track.update_columns(status: 'finalizing', updated_at: 11.minutes.ago)
    stub_fal_status('req-1', 'COMPLETED')
    UserTracks::Reconcile.call(@user)
    assert_equal 'generating', track.reload.status
    assert_enqueued_with(job: UserTracks::FinalizeJob, args: [track.id])
  end

  test 'a submit lost to a restart is queued again; one lost mid-submit fails with a refund' do
    queued = create_user_track(@user)
    queued.update_columns(updated_at: 5.minutes.ago)
    UserTracks::Reconcile.call(@user)
    assert_enqueued_with(job: UserTracks::SubmitJob, args: [queued.id])

    lost = create_user_track(create(:user))
    lost.update_columns(status: 'generating', updated_at: 5.minutes.ago)
    UserTracks::Reconcile.call(lost.user)
    lost.reload
    assert_equal 'failed', lost.status
    assert lost.credit_refunded_at
  end

  # Review Focus 1: reconcile after the webhook already finalised.
  test 'reconcile after the webhook finalised does nothing' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub_fal_done
    stub_post_runner(track_analysis)
    UserTracks::FinalizeJob.perform_now(track.id)
    assert_equal 'ready', track.reload.status

    perform_enqueued_jobs { UserTracks::Reconcile.call(@user) }
    assert_requested :get, "#{FAL_QUEUE}/requests/req-1", times: 1
    assert_equal 1, ActiveStorage::Attachment.where(record_type: 'Spree::UserTrack', record_id: track.id).count
  end

  test 'index reconciles and shows the true status' do
    track = generating_track(@user, submitted_at: 5.minutes.ago)
    stub_fal_status('req-1', 'COMPLETED', error: 'boom')
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get '/api/v1/user_tracks', headers: auth(@user)
    assert_equal 200, session.response.status
    body = JSON.parse(session.response.body)
    assert_equal [[track.id.to_s, 'failed', true]], body.map { |t| [t['id'], t['status'], t['creditRefunded']] }
  end
end
