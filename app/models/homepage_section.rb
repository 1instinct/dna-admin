class HomepageSection < Spree::Base
  # Validations
  validates :title, presence: true
  validates :section_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  
  # Scopes
  default_scope { order(position: :asc) }
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
  
  # Set position before create
  before_create :set_position
  
  private
  
  def set_position
    self.position ||= HomepageSection.maximum(:position).to_i + 1
  end
end
