class MenuItem < Spree::Base
  before_create :set_item_position
  before_save :assign_default_values
  # Before the childrens association's dependent destroy, which would otherwise delete them first.
  before_destroy :keep_items_with_children, prepend: true
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
  def child_chain(visited_ids = [])
    return [self] if visited_ids.include?(id)
    
    visited_ids << id
    result = [self]
    
    childrens.each do |child|
      result += child.child_chain(visited_ids.dup)
    end
    
    result
  end

  protected

  # An item with children is deleted only along with its parent or menu location, as in the admin
  # (MenuItemsController#destroy): its children are deleted or moved first.
  def keep_items_with_children
    return if destroyed_by_association
    return unless childrens.exists?

    errors.add(:base, 'Delete or move its child items first.')
    throw :abort
  end

  def set_item_position
    self.position = MenuItem.where(parent_id: parent_id).count
  end

  def assign_default_values
    %w(url item_class item_id item_target parent_id).each do |key|
      self[key] = nil if self[key].blank?
    end
  end
end
