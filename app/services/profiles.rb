# Public user profiles: handles, blocks and content reports.
#
# Settings live on Profiles.config. Word lists load from config/moderation/:
#   reserved_handles.yml and blocked_terms.yml (shipped here), plus any app file named
#   *_reserved_handles.yml or *_blocked_terms.yml in the same folder (an app appends to the
#   lists by adding its own file). Each file holds a YAML list of strings.
# The moderation inbox comes from ENV['MODERATION_EMAIL'].
module Profiles
  class Config
    attr_writer :reserved_handles, :blocked_terms, :moderation_email
    attr_accessor :extra_reserved_handles, :links_keys, :handle_cooldown, :report_limit,
                  :report_window, :avatar_max_bytes, :avatar_content_types, :avatar_size,
                  :avatar_variants, :moderation_dir, :favorites_limit, :avatar_fallback

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
      # avatar URL column). Returns the same URL for every size.
      @avatar_fallback = nil
    end

    # Lowercase handles nobody may take.
    def reserved_handles
      @reserved_handles ||= Set.new((load_list('reserved_handles') + extra_reserved_handles).map { |h| h.to_s.downcase })
    end

    # Lowercase terms refused in handles (substring) and in names and bios (whole words).
    def blocked_terms
      @blocked_terms ||= load_list('blocked_terms').map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
    end

    def moderation_email
      defined?(@moderation_email) ? @moderation_email : ENV['MODERATION_EMAIL'].presence
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
