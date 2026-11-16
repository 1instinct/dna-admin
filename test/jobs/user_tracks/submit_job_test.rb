require 'test_helper'

class UserTracks::SubmitJobTest < ActiveJob::TestCase
  BASE = 'https://queue.fal.run/fal-ai/ace-step-1.5'.freeze
  KEY = 'fal-test-key-SECRET-123'.freeze

  setup do
    setup_user_tracks
    @user = create(:user)
    @track = create_user_track(@user)
  end

  teardown { reset_user_tracks! }

  def stub_submit(request_id = 'req-1')
    stub_request(:post, BASE).with(query: hash_including({})).
      to_return(status: 200, body: { request_id: request_id }.to_json)
  end

  test 'submits the input with the track webhook, records the attempt and moves to generating' do
    stub = stub_submit
    UserTracks::SubmitJob.perform_now(@track.id)

    hook = "https://admin.example.test/api/v1/user_tracks/webhook/#{@track.webhook_token}"
    assert_requested(:post, BASE, query: { 'fal_webhook' => hook }, times: 1) do |req|
      body = JSON.parse(req.body)
      assert_equal %w[bpm duration key_scale lyrics prompt seed thinking time_signature], body.keys.sort
      assert_equal 48.0, body['duration']
      assert_equal 'A Minor', body['key_scale']
      assert_equal "Key #{KEY}", req.headers['Authorization']
      true
    end
    assert_requested stub

    @track.reload
    assert_equal 'generating', @track.status
    gen = @track.generation
    assert_equal 'fal', gen['provider']
    assert_equal 'fal-ai/ace-step-1.5', gen['model']
    assert_equal ['req-1'], gen['requestIds']
    assert_equal 'req-1', gen['requestId']
    assert_equal 1, gen['attempts']
    assert_equal 1, gen['seeds'].size
    assert_in_delta 0.0144, gen['costUsd'], 1e-9
    assert @track.submitted_at
  end

  test 'a second attempt appends its seed and request id and adds its cost' do
    stub_submit('req-1')
    UserTracks::SubmitJob.perform_now(@track.id)
    @track.update_columns(status: 'queued')
    WebMock.reset!
    stub_submit('req-2')
    UserTracks::SubmitJob.perform_now(@track.id)

    gen = @track.reload.generation
    assert_equal %w[req-1 req-2], gen['requestIds']
    assert_equal 'req-2', gen['requestId']
    assert_equal 2, gen['seeds'].size
    refute_equal gen['seeds'][0], gen['seeds'][1]
    assert_equal 2, gen['attempts']
    assert_in_delta 0.0288, gen['costUsd'], 1e-9
  end

  test 'while a regeneration is being submitted, the previous attempt is not finalised again' do
    @track.update_columns(generation: { 'requestId' => 'req-1', 'requestIds' => ['req-1'], 'attempts' => 1 })
    claimed_mid_submit = nil
    stub_request(:post, BASE).with(query: hash_including({})).to_return do |_req|
      UserTracks::FinalizeJob.perform_now(@track.id)
      claimed_mid_submit = Spree::UserTrack.find(@track.id).status
      { status: 200, body: { request_id: 'req-2' }.to_json }
    end
    UserTracks::SubmitJob.perform_now(@track.id)

    assert_equal 'generating', claimed_mid_submit
    assert_not_requested :get, /requests\/req-1/
    assert_equal 'req-2', @track.reload.generation['requestId']
  end

  test 'runs once: a track no longer queued, or deleted, is left alone' do
    stub = stub_submit
    UserTracks::SubmitJob.perform_now(@track.id)
    UserTracks::SubmitJob.perform_now(@track.id)
    assert_requested stub, times: 1

    deleted = create_user_track(create(:user))
    UserTracks::Removal.call(deleted)
    UserTracks::SubmitJob.perform_now(deleted.id)
    assert_equal 'queued', deleted.reload.status
    assert_requested stub, times: 1

    UserTracks::SubmitJob.perform_now(0)
  end

  test 'a provider failure fails the track and refunds its credit' do
    stub_request(:post, /queue.fal.run/).to_return(status: 500)
    UserTracks::SubmitJob.perform_now(@track.id)
    @track.reload
    assert_equal 'failed', @track.status
    assert @track.credit_refunded_at
    assert @track.error.present?
    assert_equal 'provider_unavailable', @track.generation['failure']
  end

  test 'the fal key never reaches the log' do
    stub_submit
    log = captured_log { UserTracks::SubmitJob.perform_now(@track.id) }
    assert_includes log, "track #{@track.id} submitted"
    refute_includes log, KEY

    track = create_user_track(create(:user))
    stub_request(:post, /queue.fal.run/).to_return(status: 403, body: { detail: KEY }.to_json)
    log = captured_log { UserTracks::SubmitJob.perform_now(track.id) }
    refute_includes log, KEY
  end
end
