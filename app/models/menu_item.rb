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

  # Storefront path patterns for typed links, one per kind. A storefront with other routes sets
  # MENU_PRODUCT_PATH, MENU_TAXON_PATH or MENU_PAGE_PATH; %{slug}, %{permalink}, %{name} and
  # %{id} are filled in (the name URL-encoded).
  LINK_PATHS = {
    'product' => -> { ENV['MENU_PRODUCT_PATH'].presence || '/%{slug}' },
    'taxon' => -> { ENV['MENU_TAXON_PATH'].presence || '/browse?categories=%{name}' },
    'page' => -> { ENV['MENU_PAGE_PATH'].presence || '%{slug}' }
  }.freeze

  # Where the item points on the storefront. A URL link (or an older item whose item_class is a
  # CSS class) is its url; a product, taxon or page link is built from the record now, so it
  # follows slug and name changes. A missing record falls back to the stored url.
  def storefront_url
    kind = item_class.to_s
    return url.to_s unless LINK_PATHS.key?(kind) && item_id.present?

    values = link_values(kind)
    return url.to_s unless values

    pattern = LINK_PATHS.fetch(kind).call
    # Slugs and permalinks are already path-safe (a page slug keeps its slashes); a name is encoded.
    format(pattern, values.merge(name: ERB::Util.url_encode(values[:name].to_s)))
  rescue KeyError, ArgumentError
    url.to_s
  end

  protected

  def link_values(kind)
    case kind
    when 'product'
      product = Spree::Product.find_by(id: item_id)
      product && { slug: product.slug, id: product.id, name: product.name, permalink: product.slug }
    when 'taxon'
      taxon = Spree::Taxon.find_by(id: item_id)
      taxon && { slug: taxon.permalink, permalink: taxon.permalink, name: taxon.name, id: taxon.id }
    when 'page'
      page = defined?(Spree::Page) && Spree::Page.find_by(id: item_id)
      return nil unless page
      return { slug: page.foreign_link, id: page.id, name: page.title, permalink: page.foreign_link } if page.respond_to?(:foreign_link) && page.foreign_link.present?

      slug = page.slug.to_s
      slug = "/#{slug}" unless slug.start_with?('/')
      { slug: slug, id: page.id, name: page.title, permalink: slug }
    end
  end

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
