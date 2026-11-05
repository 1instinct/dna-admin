class AdminTheme < Spree::Base
  has_one_attached :logo
  has_one_attached :favicon

  validates :primary_color, :secondary_color, :surface_color,
            :background_color, :text_color, :sidebar_color,
            format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a valid hex color" }
  validates :color_mode, inclusion: { in: %w[light dark system] }
  validates :border_radius, format: { with: /\A\d+px\z/ }
  validates :brand_name, length: { maximum: 100 }
  validates :font_family, format: { with: /\A[a-zA-Z0-9\s,\-\+\.\']+\z/, message: "contains invalid characters" }
  validate  :acceptable_logo
  validate  :acceptable_favicon
  validate  :safe_custom_css

  before_validation -> { self.singleton_guard = 0 }

  CACHE_KEY = 'admin_theme/current'.freeze
  CACHE_TTL = 5.minutes

  # Mirrors the column defaults in the create_admin_themes migration. Used to
  # render the admin layout before that migration has run.
  DEFAULTS = {
    brand_name: 'Admin',
    primary_color: '#6366f1',
    secondary_color: '#8b5cf6',
    surface_color: '#1a1a2e',
    background_color: '#0f0f1a',
    text_color: '#e2e8f0',
    sidebar_color: '#16162a',
    border_radius: '8px',
    font_family: 'Inter, system-ui, sans-serif',
    color_mode: 'system',
    enable_animations: true,
    custom_css: nil
  }.freeze

  # Stand-in for an ActiveStorage attachment when the table is missing.
  class MissingAttachment
    def attached?
      false
    end
  end

  # Read-only default theme returned while the admin_themes table does not
  # exist yet (e.g. deployed but not migrated), so admin pages still render.
  Fallback = Struct.new(*DEFAULTS.keys, keyword_init: true) do
    def logo
      MissingAttachment.new
    end

    def favicon
      MissingAttachment.new
    end

    def persisted?
      false
    end
  end

  def self.current
    return Fallback.new(**DEFAULTS) unless table_exists?

    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      first_or_create!
    end
  end

  def self.bust_cache!
    Rails.cache.delete(CACHE_KEY)
  end

  FONT_PRESETS = [
    'Inter, system-ui, sans-serif',
    'Plus Jakarta Sans, system-ui, sans-serif',
    'DM Sans, system-ui, sans-serif',
    'Geist, system-ui, sans-serif',
    'system-ui, -apple-system, sans-serif'
  ].freeze

  # SVG is deliberately excluded: Rails serves SVG blobs as attachments
  # (download), so an SVG logo/favicon would not render.
  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/webp image/x-icon].freeze
  MAX_LOGO_SIZE = 2.megabytes
  MAX_FAVICON_SIZE = 500.kilobytes

  # Custom CSS is rendered raw inside a <style> tag on every admin page, so
  # anything that could break out of the tag, run script, or load/send data
  # to another host is rejected.
  DANGEROUS_CSS_PATTERNS = [
    %r{</style}i,
    %r{<script}i,
    /</,
    />/,
    /\\/,
    /expression\s*\(/i,
    /@import/i,
    /javascript:/i,
    /image-set\s*\(/i
  ].freeze

  # url(...) values are only allowed when they point at a relative path on
  # this host or an inline data: image.
  CSS_URL_PATTERN = /url\s*\(\s*(['"]?)(.*?)\1\s*\)/im
  CSS_URL_OPENER = /url\s*\(/i
  SAFE_CSS_URL = %r{\A(?:data:image/[a-z0-9.+-]+[;,]|(?![a-z][a-z0-9+.-]*:)(?!//)[^\s'"()]*\z)}i

  def self.unsafe_css?(css)
    return false if css.blank?
    return true if DANGEROUS_CSS_PATTERNS.any? { |pattern| css.match?(pattern) }

    urls = css.scan(CSS_URL_PATTERN).map(&:last)
    return true if urls.size != css.scan(CSS_URL_OPENER).size

    urls.any? { |url| !url.strip.match?(SAFE_CSS_URL) }
  end

  private

  def acceptable_logo
    return unless logo.attached?
    errors.add(:logo, "must be an image") unless logo.blob.content_type.in?(ALLOWED_IMAGE_TYPES)
    errors.add(:logo, "must be less than 2MB") if logo.blob.byte_size > MAX_LOGO_SIZE
  end

  def acceptable_favicon
    return unless favicon.attached?
    errors.add(:favicon, "must be an image") unless favicon.blob.content_type.in?(ALLOWED_IMAGE_TYPES)
    errors.add(:favicon, "must be less than 500KB") if favicon.blob.byte_size > MAX_FAVICON_SIZE
  end

  def safe_custom_css
    return if custom_css.blank?
    if self.class.unsafe_css?(custom_css)
      errors.add(:custom_css, "contains potentially dangerous content")
    end
  end
end
