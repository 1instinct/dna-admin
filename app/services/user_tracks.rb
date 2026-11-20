# AI backing tracks: a signed-in user asks for a loop in a style, at their session's tempo, key,
# time signature and length in bars. A generator (fal.ai's queue) makes it, a post-processing
# script cuts a seamless whole-bar loop and measures it, and the loop is stored as the user's
# private Spree::UserTrack. Settings live on UserTracks.config.
#
# ENV:
#   FAL_KEY                       fal.ai API key (generation is refused while unset)
#   USER_TRACKS_WEBHOOK_HOST      public base URL fal calls back, e.g. https://admin.example.com
#                                 (without it, tracks finish through reconcile only)
#   USER_TRACKS_MONTHLY_FREE      tracks per user per calendar month (UTC), default 20
#   USER_TRACKS_DAILY_BUDGET_USD  estimated generator spend per UTC day before new tracks are
#                                 refused with 503 busy, default 10
#   USER_TRACKS_HOURLY_LIMIT      tracks a user may start per rolling hour, default 10
#   USER_TRACK_STYLES             style vocabulary file, relative to the app root, default
#                                 config/user_track_styles.yml
#   USER_TRACKS_PYTHON            python interpreter for the post-processing script, default python3
module UserTracks
  class Config
    attr_writer :fal_key, :webhook_host, :monthly_free, :daily_budget_usd, :hourly_limit, :styles_path, :python
    attr_accessor :fal_queue_base, :fal_model, :price_per_second, :max_duration, :reconcile_after,
                  :finalizing_stale_after, :give_up_after, :check_every, :signed_url_ttl, :max_download_bytes,
                  :post_timeout, :script_path, :open_timeout, :read_timeout

    def initialize
      @fal_queue_base = 'https://queue.fal.run'
      @fal_model = 'fal-ai/ace-step-1.5'
      # fal's price for ACE-Step 1.5, per second of audio asked for.
      @price_per_second = 0.0003
      # Longest audio asked of the generator, in seconds.
      @max_duration = 120.0
      # A generating track this old is checked against the provider when its owner lists tracks.
      @reconcile_after = 4.minutes
      # A finalizing track this old lost its job (a dyno restart) and is finalised again.
      @finalizing_stale_after = 10.minutes
      # A track still not done this long after its last submit fails, with its credit refunded.
      @give_up_after = 20.minutes
      # The provider is asked about one track at most this often.
      @check_every = 20.seconds
      @signed_url_ttl = 5.minutes
      @max_download_bytes = 80.megabytes
      @post_timeout = 180
      @script_path = Rails.root.join('lib', 'user_tracks', 'track_post.py')
      @open_timeout = 5
      @read_timeout = 15
    end

    def fal_key
      defined?(@fal_key) ? @fal_key : ENV['FAL_KEY'].presence
    end

    def webhook_host
      value = defined?(@webhook_host) ? @webhook_host : ENV['USER_TRACKS_WEBHOOK_HOST'].presence
      return if value.blank?

      value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)
      value.chomp('/')
    end

    def monthly_free
      defined?(@monthly_free) ? @monthly_free : int_env('USER_TRACKS_MONTHLY_FREE', 20)
    end

    def daily_budget_usd
      defined?(@daily_budget_usd) ? @daily_budget_usd : float_env('USER_TRACKS_DAILY_BUDGET_USD', 10.0)
    end

    def hourly_limit
      defined?(@hourly_limit) ? @hourly_limit : int_env('USER_TRACKS_HOURLY_LIMIT', 10)
    end

    def styles_path
      path = defined?(@styles_path) ? @styles_path : ENV.fetch('USER_TRACK_STYLES', 'config/user_track_styles.yml')
      Rails.root.join(path.to_s)
    end

    def python
      defined?(@python) ? @python : ENV.fetch('USER_TRACKS_PYTHON', 'python3')
    end

    private

    def int_env(name, default)
      Integer(ENV[name].to_s, exception: false) || default
    end

    def float_env(name, default)
      Float(ENV[name].to_s, exception: false) || default
    end
  end

  class << self
    def config
      @config ||= Config.new
    end

    # Tests use this to drop overrides.
    def reset_config!
      @config = nil
      UserTracks::Styles.reset!
    end

    # Runs the block with the logger at INFO or above, so URLs ActiveStorage generates (logged at
    # DEBUG, signed) never reach the log.
    def quietly(&block)
      logger = Rails.logger
      return yield unless logger.respond_to?(:silence)

      logger.silence(::Logger::INFO, &block)
    end
  end
end
