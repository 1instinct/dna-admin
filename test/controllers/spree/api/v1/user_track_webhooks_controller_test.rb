require 'test_helper'

# POST /api/v1/user_tracks/webhook?webhook_token=: fal's callback. No auth; the token names the track.
# It only triggers finalising: Rails fetches the result with its own key, never from the body.
class Spree::Api::V1::UserTrackWebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    setup_user_tracks
    @user = create(:user)
    @track = generating_track(@user)
  end

  teardown { reset_user_tracks! }

  def hook(token, body = {})
    post "/api/v1/user_tracks/webhook?webhook_token=#{CGI.escape(token.to_s)}", params: body, as: :json
  end

  # What fal posts, with a result that must not be used.
  def forged_body
    { request_id: 'req-1', status: 'OK',
      payload: { audio: { url: 'https://evil.example/forged.flac', content_type: 'audio/flac' } } }
  end

  test 'triggers finalise, which fetches the result from fal and ignores the body' do
    stub_fal_done
    stub_post_runner(track_analysis)
    perform_enqueued_jobs { hook(@track.webhook_token, forged_body) }

    assert_response :ok
    assert_equal 'ready', @track.reload.status
    assert_requested :get, "#{FAL_QUEUE}/requests/req-1", times: 1
    assert_requested :get, 'https://v3.fal.media/files/req-1.flac', times: 1
    assert_not_requested :get, 'https://evil.example/forged.flac'
  end

  test 'a wrong or malformed token is 404 and does nothing' do
    hook("#{@track.id}-not-the-secret", forged_body)
    assert_response :not_found
    hook('garbage')
    assert_response :not_found
    assert_no_enqueued_jobs
  end

  test 'a token in the body is not used' do
    post '/api/v1/user_tracks/webhook', params: { webhook_token: @track.webhook_token }, as: :json
    assert_response :not_found
    assert_no_enqueued_jobs
  end

  test 'the token never reaches the log' do
    log = captured_log { hook(@track.webhook_token, forged_body) }
    assert_response :ok
    assert_includes log, '/api/v1/user_tracks/webhook?webhook_token=[FILTERED]'
    refute_includes log, @track.webhook_secret
  end

  test 'the body (fal\'s audio URL) never reaches the log' do
    body = { request_id: 'req-1', status: 'OK', error: nil,
             payload: { audio: { url: 'https://v3.fal.media/files/secret-result-path.flac', file_size: 123 } } }
    log = captured_log { hook(@track.webhook_token, body) }
    assert_response :ok
    assert_includes log, 'Parameters:'
    refute_includes log, 'secret-result-path'
    refute_includes log, 'v3.fal.media'
    refute_includes log, 'req-1'
  end

  # Review Focus 1.
  test 'a double webhook finalises once: one attachment, one status change' do
    stub_fal_done
    stub_post_runner(track_analysis)
    perform_enqueued_jobs do
      hook(@track.webhook_token, forged_body)
      hook(@track.webhook_token, forged_body)
    end
    assert_response :ok
    assert_equal 'ready', @track.reload.status
    assert_equal 1, ActiveStorage::Attachment.where(record_type: 'Spree::UserTrack', record_id: @track.id).count
    assert_requested :get, "#{FAL_QUEUE}/requests/req-1", times: 1
  end

  # Review Focus 2.
  test 'a webhook for a track deleted mid-generation is a no-op' do
    UserTracks::Removal.call(@track)
    perform_enqueued_jobs { hook(@track.webhook_token, forged_body) }
    assert_response :ok
    assert_not_requested :any, /fal/
    assert_equal 0, ActiveStorage::Blob.count
  end
end
