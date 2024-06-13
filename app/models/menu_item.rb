class MenuItem < Spree::Base
  before_create :set_item_position
  before_save :assign_default_values
  belongs_to :menu_location,
              foreign_key: :menu_location_id
  belongs_to :parent,
             foreign_key: :parent_id,
             class_name: 'MenuItem',
             optional: true
  has_many :childrens,
           class_name: 'MenuItem',
           foreign_key: :parent_id,
           dependent: :destroy

  validates :name, presence: true

  default_scope { order(position: :asc) }

  scope :top_level, -> { where(parent_id: nil) }

  protected

  def set_item_position
    self.position = MenuItem.where(parent_id: parent_id).count
  end

  def assign_default_values
    %w(url item_class item_id item_target parent_id).each do |key|
      self[key] = nil if self[key].blank?
    end
  end
end
