module AdminNative
  # The admin app's menu builder (config/initializers/spree_admin_native_resources.rb, companion
  # gem 0.7 tree views): menu_items is one tree per menu location, reordered with PATCH
  # resources/menu_items/tree; menu_locations is hidden and managed from the tree screen.
  #
  # item_class and item_id are a typed link: item_class holds the kind (url, product, taxon or
  # page) and item_id the record. An older item_class (a CSS class name) reads as the item's URL.
  # The storefront reads url, which a URL link keeps.
  module Menus
    LINK_KINDS = { 'product' => 'spree_products', 'taxon' => 'spree_taxons', 'page' => 'pages' }.freeze

    module_function

    def locations(r)
      r.model 'MenuLocation'
      r.label 'Menu locations'
      r.group 'Storefront'
      r.icon 'list.bullet.rectangle'
      r.title :title
      r.subtitle :location
      r.list :title, :location, :is_visible
      r.search :title, :location
      r.filter :is_visible
      r.order :created_at, :desc
      r.field :title, :string
      r.field :location, :string
      r.field :is_visible, :boolean, label: 'Visible'
      r.field :created_at
      r.field :updated_at
      # The menu builder adds, renames and deletes locations; hidden types still take CRUD.
      r.hidden
    end

    def items(r)
      r.model 'MenuItem'
      r.label 'Menus'
      r.singular 'Menu item'
      r.group 'Storefront'
      r.icon 'list.bullet.indent'
      r.title :name
      r.subtitle :url
      r.list :name, :link, :is_visible
      r.search :name, :url
      r.filter :menu_location_id
      r.order :position, :asc
      r.field :name, :string
      r.field :menu_location_id, :reference, resource: 'menu_locations', label: 'Menu'
      r.field :parent_id, :reference, resource: 'menu_items', label: 'Parent item'
      r.field :position, :integer
      r.field :link, :link, label: 'Link', url: :url, kind: :item_class, id: :item_id, kinds: LINK_KINDS
      r.field :item_target, :string, label: 'Link target'
      # Not in the admin's permitted params.
      r.field :is_visible, :boolean, label: 'Visible', readonly: true
      r.field :created_at
      r.field :updated_at
      r.view :tree, parent: :parent_id, position: :position, group: :menu_location_id
      # MenuItem refuses to delete an item with children, as in the admin; the app doesn't offer it.
      # Moving items (the tree's reorder) is fine: the gem writes moves with update_columns.
      r.deletable_if ->(item) { item.childrens.none? }
    end
  end
end
