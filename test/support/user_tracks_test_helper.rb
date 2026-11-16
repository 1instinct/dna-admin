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
