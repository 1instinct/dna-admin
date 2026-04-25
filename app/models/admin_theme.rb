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

  def self.current
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

  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/webp image/svg+xml image/x-icon].freeze
  MAX_LOGO_SIZE = 2.megabytes
  MAX_FAVICON_SIZE = 500.kilobytes

  DANGEROUS_CSS_PATTERNS = [
    %r{</style>}i,
    %r{<script}i,
    /</,
    />/,
    /expression\s*\(/i,
    %r{url\s*\(\s*javascript:}i,
    %r{@import\s+url\s*\(\s*["']?\s*javascript:}i
  ].freeze

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
    if DANGEROUS_CSS_PATTERNS.any? { |pattern| custom_css.match?(pattern) }
      errors.add(:custom_css, "contains potentially dangerous content")
    end
  end
end
