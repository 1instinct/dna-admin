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
  ].freeze
  
  validates :section_type, inclusion: { in: SECTION_TYPES }
  
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
  
  def set_position
    if self.position.nil? || self.position.zero?
      self.position = (HomepageSection.maximum(:position) || 0) + 1
    end
  end
end
