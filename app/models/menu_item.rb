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

  def parent_chain
    Enumerator.new do |enum|
      parent_product = parent
      while !parent_product.nil?
        enum.yield parent_product
        parent_product = parent_product.parent
      end
    end.to_a.reverse + [self]
  end
  def child_chain
    Enumerator.new do |enum|
      child_products = childrens
      unless child_products.nil?
        child_products.each do |child_product|
          enum.yield child_product unless child_product.nil?
          child_products = child_product.childrens unless child_product.nil?
        end
      end
    end.to_a + [self]
  end

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
