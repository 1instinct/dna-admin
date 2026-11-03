# Public user profiles: handles, blocks and content reports.
#
# Settings live on Profiles.config. Word lists load from config/moderation/:
#   reserved_handles.yml and blocked_terms.yml (shipped here), plus any app file named
#   *_reserved_handles.yml or *_blocked_terms.yml in the same folder (an app appends to the
#   lists by adding its own file). Each file holds a YAML list of strings. A *_reserved_prefixes.yml
#   file refuses every handle starting with one of its entries; none ship here.
# The moderation inbox comes from ENV['MODERATION_EMAIL'].
# External avatar URLs are served only from the hosts in ENV['PROFILE_AVATAR_URL_HOSTS'] (comma
# separated, default none), because the host of an image sees the IP of everyone viewing it.
module Profiles
  class Config
    attr_writer :reserved_handles, :reserved_prefixes, :blocked_terms, :moderation_email, :avatar_url_hosts
    attr_accessor :extra_reserved_handles, :links_keys, :handle_cooldown, :report_limit,
                  :report_window, :avatar_max_bytes, :avatar_content_types, :avatar_size,
                  :avatar_variants, :moderation_dir, :favorites_limit, :avatar_fallback,
                  :rate_limits

    def initialize
      @extra_reserved_handles = []
      @links_keys = %w[instagram tiktok youtube soundcloud bandcamp]
      @handle_cooldown = 14.days
      @report_limit = 20
      @report_window = 24.hours
      @avatar_max_bytes = 5.megabytes
      @avatar_content_types = %w[image/jpeg image/png image/webp]
      # The stored avatar is re-encoded to this square JPEG on upload (EXIF stripped), so no
      # client original is ever kept or served.
      @avatar_size = 1024
      @avatar_variants = {
        small: { resize_to_fill: [128, 128], strip: true },
        large: { resize_to_fill: [512, 512], strip: true }
      }
      @moderation_dir = Rails.root.join('config', 'moderation')
      @favorites_limit = 24
      # Optional ->(user) { url } used for the avatar when none is attached (e.g. an app's legacy
      # avatar URL column). Returns the same URL for every size, when its host is allowed.
      @avatar_fallback = nil
      # Per-user limits, see Profiles::RateLimit. follow covers follow and unfollow, block covers
      # block and unblock. Past a limit the endpoint answers 429.
      @rate_limits = {
        follow: { limit: 120, window: 1.hour },
        block: { limit: 60, window: 1.hour },
        handle_available: { limit: 60, window: 1.minute },
        avatar: { limit: 20, window: 24.hours }
      }
    end

    # Lowercase handles nobody may take.
    def reserved_handles
      @reserved_handles ||= Set.new((load_list('reserved_handles') + extra_reserved_handles).map { |h| h.to_s.downcase })
    end

    # Lowercase prefixes nobody may start a handle with.
    def reserved_prefixes
      @reserved_prefixes ||= load_list('reserved_prefixes').map { |p| p.to_s.downcase.strip }.reject(&:empty?).uniq
    end

    # Lowercase terms refused in handles (substring) and in names and bios (whole words).
    def blocked_terms
      @blocked_terms ||= load_list('blocked_terms').map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
    end

    def moderation_email
      defined?(@moderation_email) ? @moderation_email : ENV['MODERATION_EMAIL'].presence
    end

    def avatar_url_hosts
      @avatar_url_hosts ||= ENV['PROFILE_AVATAR_URL_HOSTS'].to_s.split(',').map { |h| h.strip.downcase }.reject(&:empty?)
    end

    def avatar_url_allowed?(url)
      uri = URI.parse(url.to_s)
      uri.scheme == 'https' && uri.userinfo.nil? && avatar_url_hosts.include?(uri.host.to_s.downcase)
    rescue URI::InvalidURIError
      false
    end

    private

    def load_list(name)
      dir = Pathname.new(moderation_dir)
      files = [dir.join("#{name}.yml")] + Dir.glob(dir.join("*_#{name}.yml").to_s).sort.map { |f| Pathname.new(f) }
      files.select(&:exist?).flat_map { |f| Array(YAML.safe_load(f.read)) }
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Tests use this to drop injected lists.
  def self.reset_config!
    @config = nil
  end
end
