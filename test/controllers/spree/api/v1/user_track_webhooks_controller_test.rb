require 'test_helper'

# POST /api/v1/user_tracks/webhook/:token: fal's callback. No auth; the token names the track.
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
    post "/api/v1/user_tracks/webhook/#{token}", params: body, as: :json
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
