class HomepageSection < Spree::Base
  # Validations
  validates :section_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  
  # Scopes
  scope :ordered, -> { order(position: :asc) }
  scope :visible, -> { where(is_visible: true) }
  scope :by_type, ->(type) { where(section_type: type) }
  
  # Ransack searchable attributes
  self.whitelisted_ransackable_attributes = %w[title section_type]
  self.whitelisted_ransackable_scopes = %w[search_homepage_sections]
  
  # Available section types
  SECTION_TYPES = %w[
    hero
    features
    products
    content
    testimonials
    gallery
    call_to_action
    newsletter
    video
    live_streams
    categories
    custom
    announcement_bar
    app_links
  ].freeze
  
  validates :section_type, inclusion: { in: SECTION_TYPES }

  # Section types whose `settings` are edited as discrete form fields and
  # composed into a Hash by the controller, rather than through the raw
  # Settings (JSON) textarea.
  COMPOSED_SETTINGS_TYPES = %w[announcement_bar app_links].freeze

  # `settings` keys that end up in an href on the storefront, with the admin
  # label for each. The storefront only follows an absolute http(s) URL
  # (lib/appLinks.ts `validUrl`), so anything else there is silently discarded
  # and the site keeps showing the previous link with no error anywhere.
  # Rejecting it here is the only place an operator finds out.
  URL_SETTINGS_FIELDS = {
    'app_links' => { 'ios_url' => 'iOS App Store URL', 'android_url' => 'Google Play URL' },
    'announcement_bar' => { 'cta_href' => 'Button link' }
  }.freeze

  ABSOLUTE_HTTP_URL = %r{\Ahttps?://\S}i.freeze

  validate :callout_urls_are_absolute

  def composed_settings?
    COMPOSED_SETTINGS_TYPES.include?(section_type)
  end

  # Search scope
  def self.search_homepage_sections(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:title).where(
        "LOWER(#{table_name}.title) LIKE LOWER(:query) OR LOWER(content) LIKE LOWER(:query)", 
        query: "%#{query}%"
      ).distinct
    else
      where(
        "LOWER(#{table_name}.title) LIKE LOWER(:query) OR LOWER(content) LIKE LOWER(:query)", 
        query: "%#{query}%"
      )
    end
  end
  
  # Set position before validation on create
  before_validation :set_position, on: :create
  
  # Class method to reset all positions sequentially
  def self.reset_positions!
    unscoped.order(:id).each_with_index do |section, index|
      section.update_column(:position, index + 1)
    end
  end
  
  private

  def callout_urls_are_absolute
    fields = URL_SETTINGS_FIELDS[section_type]
    return if fields.nil?
    return unless settings.is_a?(Hash)

    fields.each do |key, label|
      value = settings[key].to_s.strip
      next if value.empty?
      next if value.match?(ABSOLUTE_HTTP_URL)

      errors.add(
        :base,
        "#{label} must be a full URL starting with http:// or https:// (got \"#{value}\")"
      )
    end
  end

  def set_position
    if self.position.nil? || self.position.zero?
      self.position = (HomepageSection.maximum(:position) || 0) + 1
    end
  end
end
