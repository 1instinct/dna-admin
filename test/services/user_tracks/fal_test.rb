require 'test_helper'

class UserTracks::FalTest < ActiveSupport::TestCase
  BASE = 'https://queue.fal.run/fal-ai/ace-step-1.5'.freeze
  KEY = 'fal-test-key-SECRET-123'.freeze

  setup { setup_user_tracks }
  teardown { reset_user_tracks! }

  def fal
    UserTracks::Fal.new
  end

  def assert_fal_error(code)
    error = assert_raises(UserTracks::Fal::Error) { yield }
    assert_equal code, error.code
    error
  end

  test 'submit posts the input with the key and the webhook, and answers the request id' do
    hook = 'https://admin.example.test/api/v1/user_tracks/webhook/1-abc'
    stub = stub_request(:post, BASE).
           with(query: { 'fal_webhook' => hook }, headers: { 'Authorization' => "Key #{KEY}" },
                body: { prompt: 'p', seed: 1 }.to_json).
           to_return(status: 200, body: { request_id: 'req-1', status_url: "#{BASE}/requests/req-1/status",
                                         response_url: "#{BASE}/requests/req-1" }.to_json)
    assert_equal 'req-1', fal.submit({ prompt: 'p', seed: 1 }, webhook_url: hook)
    assert_requested stub
  end

  test 'submit without a webhook host sends no fal_webhook' do
    stub = stub_request(:post, BASE).to_return(status: 200, body: { request_id: 'req-2' }.to_json)
    fal.submit({ prompt: 'p' }, webhook_url: nil)
    assert_requested stub # the stub has no query, so it matches only a URL without one
  end

  test 'status maps the queue states; a completed request with an error, or an unknown one, failed' do
    { 'IN_QUEUE' => :in_queue, 'IN_PROGRESS' => :in_progress, 'COMPLETED' => :completed }.each do |raw, want|
      stub_request(:get, "#{BASE}/requests/r1/status").to_return(status: 200, body: { status: raw }.to_json)
      assert_equal want, fal.status('r1')
      WebMock.reset!
    end
    stub_request(:get, "#{BASE}/requests/r1/status").
      to_return(status: 200, body: { status: 'COMPLETED', error: 'boom', error_type: 'x' }.to_json)
    assert_equal :failed, fal.status('r1')
    WebMock.reset!
    stub_request(:get, "#{BASE}/requests/r1/status").to_return(status: 404, body: '{}')
    assert_equal :failed, fal.status('r1')
  end

  test 'result answers the audio URL' do
    stub_request(:get, "#{BASE}/requests/r1").
      to_return(status: 200, body: { audio: { url: 'https://v3.fal.media/files/x/out.flac', content_type: 'audio/flac' },
                                     seed: 5 }.to_json)
    assert_equal({ audio_url: 'https://v3.fal.media/files/x/out.flac', content_type: 'audio/flac' }, fal.result('r1'))
  end

  test 'a result without audio, or refused, failed; a server error is unreachable' do
    stub_request(:get, "#{BASE}/requests/r1").to_return(status: 200, body: { detail: 'nope' }.to_json)
    assert_fal_error(:failed) { fal.result('r1') }
    WebMock.reset!
    stub_request(:get, "#{BASE}/requests/r1").to_return(status: 422, body: { detail: 'bad' }.to_json)
    assert_fal_error(:failed) { fal.result('r1') }
    WebMock.reset!
    stub_request(:get, "#{BASE}/requests/r1").to_return(status: 200, body: { audio: { url: 'http://insecure/x.flac' } }.to_json)
    assert_fal_error(:failed) { fal.result('r1') }
    WebMock.reset!
    stub_request(:get, "#{BASE}/requests/r1").to_return(status: 503)
    assert_fal_error(:unreachable) { fal.result('r1') }
    WebMock.reset!
    stub_request(:get, "#{BASE}/requests/r1").to_timeout
    assert_fal_error(:unreachable) { fal.result('r1') }
  end

  test 'request ids are checked before they go into a URL' do
    assert_fal_error(:failed) { fal.status('../../x') }
    assert_fal_error(:failed) { fal.result('a/b') }
  end

  test 'without a key nothing is sent' do
    UserTracks.config.fal_key = nil
    refute fal.configured?
    assert_fal_error(:not_configured) { fal.submit({ prompt: 'p' }, webhook_url: nil) }
    assert_not_requested :any, /fal\.run/
  end

  test 'the key never appears in the log or in error messages' do
    stub_request(:post, BASE).to_return(status: 401, body: { detail: "bad key #{KEY}" }.to_json)
    error = nil
    log = captured_log do
      error = assert_fal_error(:unauthorized) { fal.submit({ prompt: 'p' }, webhook_url: nil) }
      Rails.logger.info('[user_tracks] test marker')
    end
    assert_includes log, 'test marker'
    assert_includes log, '[user_tracks] fal'
    refute_includes log, KEY
    refute_includes error.message, KEY
  end
end
