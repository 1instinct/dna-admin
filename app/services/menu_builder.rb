# The Rails admin's menu builder (/admin/menus, Spree::Admin::MenusController): one tree of menu
# items per menu location, with the same rules as the admin app's tree screen. Moves go through
# the companion gem's SpreeAdminNative::Tree over the menu_items type that AdminNative::Menus
# registers (cycle checks, items outside the location refused, positions renumbered 0..n per
# parent in one locked transaction), so the web admin and the app can't disagree.
#
# Links are the same typed link as the app's: item_class holds the kind (url, product, taxon or
# page) and item_id the record; the kinds offered are the ones whose type the store registers.
class MenuBuilder
  class Refused < StandardError
    attr_reader :code, :status

    def initialize(code, message, status = :unprocessable_entity)
      super(message)
      @code = code
      @status = status
    end
  end

  RESOURCE_KEY = 'menu_items'.freeze
  TARGETS = %w[_self _blank].freeze

  attr_reader :location

  def initialize(location)
    @location = location
  end

  # The registered menu_items type (config/initializers/spree_admin_native_resources.rb).
  def self.definition
    definition = SpreeAdminNative.resources[RESOURCE_KEY]
    raise Refused.new('unavailable', 'Menu items are not registered with a tree view.') unless definition&.tree_view

    definition
  end

  def self.link_field
    definition.resolved_field(:link)
  end

  # [{ kind:, label:, resource: }] for the link kind select: url first, then each record kind the
  # store has (a fork without static pages has no page kind).
  def self.link_kinds
    field = link_field
    kinds = field ? field.link_kinds : [{ kind: 'url' }]
    kinds.map { |k| k.merge(label: k[:kind] == 'url' ? 'URL' : k[:kind].to_s.humanize) }
  end

  # Nested nodes for the location: [{ id, name, url, link, item_target, is_visible, children }].
  def tree
    rows = gem_tree.records
    present_nodes(gem_tree.nest(rows), link_titles(rows))
  rescue SpreeAdminNative::Tree::Refused => e
    raise Refused.new(e.code, e.message, e.status)
  end

  # nodes: [{ id, parent_id, position }]. Returns the new tree; Refused leaves the tree unchanged.
  def move!(nodes)
    gem_tree.move!(nodes)
    tree
  rescue SpreeAdminNative::Tree::Refused => e
    raise Refused.new(e.code, e.message, e.status)
  end

  # attrs: name, parent_id, link ({ kind, url?, id? }), item_target, is_visible; after_id places
  # the new item right after that sibling (else it goes last under its parent).
  def create!(attrs, after_id: nil)
    item = location.menu_items.new
    MenuItem.transaction do
      assign(item, attrs)
      item.is_visible = true if item.is_visible.nil?
      sibling = after_id.present? && items.find_by(id: after_id)
      raise Refused.new('outside_group', 'That item is not in this menu.') if after_id.present? && !sibling

      item.parent_id = sibling.parent_id if sibling
      parent = item.parent_id && items.find_by(id: item.parent_id)
      raise Refused.new('outside_group', 'The parent item is not in this menu.') if item.parent_id && !parent

      save!(item)
      if sibling
        position = (siblings_of(sibling) - [item.id]).index(sibling.id).to_i + 1
        gem_tree.move!([{ id: item.id, parent_id: sibling.parent_id, position: position }])
      else
        gem_tree.move!([{ id: item.id, parent_id: item.parent_id, position: nil }])
      end
    end
    item.reload
  rescue SpreeAdminNative::Tree::Refused => e
    raise Refused.new(e.code, e.message, e.status)
  end

  # Name, link, target and visibility (moves go through #move!).
  def update!(item, attrs)
    assign(item, attrs.except(:parent_id, 'parent_id'))
    save!(item)
    item
  end

  # An item with children is deleted only with them (with_children: true), as MenuItem requires.
  def destroy!(item, with_children: false)
    count = descendant_count(item)
    if count.positive? && !with_children
      raise Refused.new('has_children', "#{item.name} has #{count} #{'child item'.pluralize(count)}. " \
                                        'Delete them too, or move them out first.')
    end

    MenuItem.transaction do
      # Leaves first, so no item is deleted while it still has children.
      item.child_chain.reverse_each(&:destroy!)
      gem_tree.move!([]) # renumbers the remaining siblings
    end
    count + 1
  rescue ActiveRecord::RecordNotDestroyed => e
    raise Refused.new('invalid', e.record.errors.full_messages.to_sentence.presence || "Couldn't delete it.")
  end

  def items
    location.menu_items.unscope(:order)
  end

  def present(item, titles = link_titles([item]))
    link = link_of(item, titles)
    {
      id: item.id.to_s,
      name: item.name,
      url: item.storefront_url.presence,
      link: link,
      item_target: item.item_target.presence || '_self',
      is_visible: item.is_visible != false
    }
  end

  private

  def gem_tree
    @gem_tree ||= SpreeAdminNative::Tree.new(self.class.definition, group: location.id)
  end

  def present_nodes(nested, titles)
    nested.map do |(item, children)|
      present(item, titles).merge(children: present_nodes(children, titles))
    end
  end

  def siblings_of(item)
    items.where(parent_id: item.parent_id).order(:position, :id).pluck(:id)
  end

  def descendant_count(item)
    item.child_chain.size - 1
  end

  def assign(item, attrs)
    attrs = (attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs.to_h).with_indifferent_access
    item.name = attrs[:name].to_s.strip if attrs.key?(:name)
    item.parent_id = attrs[:parent_id].presence if attrs.key?(:parent_id)
    if attrs.key?(:item_target)
      target = attrs[:item_target].presence
      raise Refused.new('invalid', "Target must be one of #{TARGETS.join(', ')}.") if target && !TARGETS.include?(target)

      item.item_target = target
    end
    item.is_visible = ActiveModel::Type::Boolean.new.cast(attrs[:is_visible]) != false if attrs.key?(:is_visible)
    assign_link(item, attrs[:link]) if attrs.key?(:link)
  end

  # { kind: 'url', url } or { kind, id }; blank clears the link.
  def assign_link(item, value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value = (value || {}).to_h.with_indifferent_access
    kind = value[:kind].to_s
    if kind.empty? || (kind == 'url' && value[:url].to_s.strip.empty?)
      item.url = item.item_class = item.item_id = nil
    elsif kind == 'url'
      item.url = value[:url].to_s.strip
      item.item_class = 'url'
      item.item_id = nil
    elsif (target = self.class.link_field&.link_target(kind))
      id = value[:id].to_s
      raise Refused.new('invalid', "Choose a #{kind} to link to.") if id.empty?
      unless target.relation.where(target.model_class.primary_key => id).exists?
        raise Refused.new('invalid', "That #{kind} doesn't exist.")
      end

      item.item_class = kind
      item.item_id = id
      item.url = nil
    else
      kinds = self.class.link_kinds.map { |k| k[:kind] }.join(', ')
      raise Refused.new('invalid', "Link kind must be one of #{kinds}.")
    end
  end

  def save!(item)
    return if item.save

    raise Refused.new('invalid', item.errors.full_messages.to_sentence)
  end

  # { kind => { id => title } }: one query per kind.
  def link_titles(rows)
    field = self.class.link_field
    return {} unless field

    rows.group_by { |r| r.item_class.to_s }.each_with_object({}) do |(kind, list), out|
      target = field.link_target(kind)
      next unless target

      ids = list.map { |r| r.item_id.to_s }.reject(&:empty?).uniq
      model = target.model_class
      out[kind] = model.where(model.primary_key => ids).each_with_object({}) { |r, h| h[r.id.to_s] = target.title_for(r) }
    end
  end

  def link_of(item, titles)
    kind = item.item_class.to_s
    if kind != 'url' && titles.key?(kind) && item.item_id.present?
      { kind: kind, id: item.item_id.to_s, title: titles.dig(kind, item.item_id.to_s) || "##{item.item_id}" }
    elsif item.url.present?
      { kind: 'url', url: item.url }
    end
  end
end
