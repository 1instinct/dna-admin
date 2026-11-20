# Shared helpers for the user tracks (AI backing tracks) tests.
module UserTracksTestHelper
  STYLES_FIXTURE = Rails.root.join('test', 'support', 'user_track_styles.yml')

  # Points UserTracks at the test styles and fixed settings; call from setup, with
  # reset_user_tracks! in teardown.
  def setup_user_tracks(**overrides)
    UserTracks.reset_config!
    config = UserTracks.config
    config.styles_path = STYLES_FIXTURE
    config.fal_key = 'fal-test-key-SECRET-123'
    config.webhook_host = 'https://admin.example.test'
    config.monthly_free = 20
    config.daily_budget_usd = 10
    config.hourly_limit = 10
    overrides.each { |name, value| config.public_send("#{name}=", value) }
    config
  end

  def reset_user_tracks!
    UserTracks.reset_config!
    UserTracks::Post.runner = nil if defined?(UserTracks::Post) && UserTracks::Post.respond_to?(:runner=)
  end

  def track_request(overrides = {})
    { 'style' => 'chillhop', 'moods' => ['warm'], 'bars' => 16, 'bpm' => 100, 'key' => 9, 'scale' => 'minor',
      'timeSig' => '4/4' }.merge(overrides.stringify_keys)
  end

  def create_user_track(user, attrs = {})
    request = track_request(attrs.delete(:request) || {})
    Spree::UserTrack.create!({ user: user, request: request, title: 'Chillhop in A minor' }.merge(attrs))
  end

  # A track_post result for 16 bars at 100 bpm, A minor, confidently measured.
  def track_analysis(overrides = {})
    {
      'ok' => true, 'bpm' => 100, 'bpmMeasured' => 100.2, 'bpmMatch' => 'x1', 'loopStartSec' => 2.4,
      'loopSamples' => 1_843_200, 'sampleRate' => 48_000, 'key' => 'A', 'keyPc' => 9, 'scale' => 'minor',
      'keyScore' => 0.86, 'keyMargin' => 0.22, 'keyTop3' => [['A minor', 0.86], ['C major', 0.64], ['D minor', 0.6]],
      'lufs' => -16.1, 'peakDb' => -1.2, 'lowNote' => 33, 'medianNote' => 57, 'highNote' => 81,
      'timbre' => { 'brightness' => 60, 'noisiness' => 20, 'percussiveness' => 70, 'sustain' => 50, 'density' => 40 }
    }.merge(overrides.stringify_keys)
  end

  # Not ok: no usable loop window.
  def no_window_analysis
    track_analysis('ok' => false, 'reason' => 'no_loop_window', 'bpmMatch' => nil, 'key' => nil, 'keyPc' => nil,
                   'scale' => nil, 'keyScore' => nil, 'keyMargin' => nil, 'loopSamples' => nil)
  end

  # Replaces the track_post runner: each call takes the next analysis (a Hash, or a Proc given the
  # argv), writes a fake loop to --out when ok, and prints the JSON. Returns the argv list.
  def stub_post_runner(*analyses)
    calls = []
    UserTracks::Post.runner = lambda do |argv|
      calls << argv
      item = analyses.length > 1 ? analyses.shift : analyses.first
      result = item.respond_to?(:call) ? item.call(argv) : item
      File.binwrite(argv[argv.index('--out') + 1], "fLaC-loop-#{calls.size}") if result['ok']
      "#{JSON.generate(result)}\n"
    end
    calls
  end

  # A track as SubmitJob leaves it: generating, attempt `attempts`, request id `request_id`.
  def generating_track(user, request_id: 'req-1', attempts: 1, submitted_at: Time.current, **attrs)
    track = create_user_track(user, attrs)
    track.update_columns(status: 'generating', submitted_at: submitted_at,
                         generation: { 'provider' => 'fal', 'requestId' => request_id,
                                       'requestIds' => [request_id], 'attempts' => attempts,
                                       'seeds' => Array.new(attempts) { |i| 100 + i }, 'costUsd' => 0.0144 })
    track
  end

  FAL_QUEUE = 'https://queue.fal.run/fal-ai/ace-step-1.5'.freeze

  # fal says request_id is COMPLETED, its result's audio is at audio_url, and the audio downloads.
  def stub_fal_done(request_id = 'req-1', audio_url: "https://v3.fal.media/files/#{request_id}.flac")
    stub_request(:get, "#{FAL_QUEUE}/requests/#{request_id}/status").
      to_return(status: 200, body: { status: 'COMPLETED' }.to_json)
    stub_request(:get, "#{FAL_QUEUE}/requests/#{request_id}").
      to_return(status: 200, body: { audio: { url: audio_url, content_type: 'audio/flac' } }.to_json)
    stub_request(:get, audio_url).to_return(status: 200, body: "fLaC-raw-#{request_id}")
  end

  def stub_fal_status(request_id, status, extra = {})
    stub_request(:get, "#{FAL_QUEUE}/requests/#{request_id}/status").
      to_return(status: 200, body: { status: status }.merge(extra).to_json)
  end

  # The bytes appended to log/test.log while the block runs (every log subscriber writes there).
  def captured_log
    path = Rails.root.join('log', 'test.log')
    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    start = File.exist?(path) ? File.size(path) : 0
    yield
    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    File.exist?(path) ? File.binread(path, nil, start).to_s : ''
  end
end

ActiveSupport::TestCase.include(UserTracksTestHelper)
