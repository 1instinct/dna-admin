require 'test_helper'

# The admin app's menu builder (companion gem 0.7 tree views, AdminNative::Menus): one tree per
# menu location, a typed link, hidden locations, and the older delete rule kept.
class AdminNativeMenusTest < ActionDispatch::IntegrationTest
  BASE = '/api/admin_native/v1/resources'.freeze

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @admin.generate_spree_api_key!
    @main = MenuLocation.create!(title: 'Main', location: 'header', is_visible: true)
    @footer = MenuLocation.create!(title: 'Footer', location: 'footer', is_visible: true)
    @shop = MenuItem.create!(name: 'Shop', menu_location: @main, url: '/shop')
    @mugs = MenuItem.create!(name: 'Mugs', menu_location: @main, parent: @shop, url: '/mugs')
    @about = MenuItem.create!(name: 'About', menu_location: @main, url: '/about')
    @legal = MenuItem.create!(name: 'Legal', menu_location: @footer, url: '/legal')
  end

  def call(method, path, body = nil)
    send(method, "#{BASE}#{path}", params: body&.to_json,
                                   headers: { 'X-Spree-Token' => @admin.spree_api_key, 'CONTENT_TYPE' => 'application/json' })
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def manifest_of(key)
    call(:get, '')['data'].find { |type| type['key'] == key }
  end

  def tree_names(nodes)
    nodes.map { |n| n['children'].any? ? { n['title'] || n.dig('values', 'name') => tree_names(n['children']) } : (n['title'] || n.dig('values', 'name')) }
  end

  test 'menu items declare the tree, grouped by the hidden menu locations, with a link field' do
    items = manifest_of('menu_items')
    assert_equal({ 'type' => 'tree', 'parent' => 'parent_id', 'position' => 'position', 'group' => 'menu_location_id' },
                 items['view'])
    assert_equal 'Menus', items['label']
    link = items['fields'].find { |f| f['name'] == 'link' }
    assert_equal 'link', link['type']
    # A fork without static pages (no pages type) offers the other kinds.
    kinds = %w[url product taxon] + (SpreeAdminNative.resources['pages'] ? %w[page] : [])
    assert_equal kinds, link['kinds'].map { |k| k['kind'] }
    assert_empty items['fields'].map { |f| f['name'] } & %w[url item_class item_id], 'the link owns its columns'
    assert manifest_of('menu_locations')['hidden']
    %w[contacts messages threads].each { |key| assert manifest_of(key)['hidden'], "#{key} gives way to the inbox" }
  end

  test 'GET tree returns one location nested' do
    body = call(:get, "/menu_items/tree?group=#{@main.id}")

    assert_response :success
    assert_equal({ 'id' => @main.id.to_s, 'title' => 'Main' }, body.dig('meta', 'group').slice('id', 'title'))
    assert_equal [@shop.id.to_s, @about.id.to_s], body['data'].map { |n| n['id'] }
    assert_equal [@mugs.id.to_s], body['data'].first['children'].map { |n| n['id'] }
  end

  test 'PATCH tree reorders, indents and outdents, renumbering positions' do
    body = call(:patch, '/menu_items/tree', { group: @main.id, nodes: [
                  { id: @about.id, parent_id: nil, position: 0 },
                  { id: @mugs.id, parent_id: nil, position: 2 },
                  { id: @shop.id, parent_id: @about.id, position: 0 }
                ] })

    assert_response :success
    assert_equal [@about.id.to_s, @mugs.id.to_s], body['data'].map { |n| n['id'] }
    assert_equal [[nil, 0], [@about.id, 0], [nil, 1]],
                 [@about, @shop, @mugs].map { |i| i.reload.values_at(:parent_id, :position) }
  end

  test 'PATCH tree refuses a node from another location and a cycle' do
    call(:patch, '/menu_items/tree', { group: @main.id, nodes: [{ id: @legal.id, parent_id: nil, position: 0 }] })
    assert_response :unprocessable_entity

    call(:patch, '/menu_items/tree', { group: @main.id, nodes: [{ id: @shop.id, parent_id: @mugs.id, position: 0 }] })
    assert_response :unprocessable_entity
    assert_nil @shop.reload.parent_id
  end

  test 'links read and write as a URL or a record' do
    product = Spree::Product.create!(name: 'Mug', price: 10, shipping_category: Spree::ShippingCategory.first_or_create!(name: 'Default'))
    call(:patch, "/menu_items/#{@shop.id}", { values: { link: { kind: 'product', id: product.id.to_s } } })
    assert_response :success
    assert_equal ['product', product.id.to_s, nil], @shop.reload.values_at(:item_class, :item_id, :url)

    body = call(:get, "/menu_items/#{@shop.id}")
    assert_equal({ 'kind' => 'product', 'id' => product.id.to_s, 'title' => 'Mug' }, body.dig('data', 'values', 'link').slice('kind', 'id', 'title'))

    @about.update_columns(item_class: 'nav-highlight')
    assert_equal({ 'kind' => 'url', 'url' => '/about' },
                 call(:get, "/menu_items/#{@about.id}").dig('data', 'values', 'link').slice('kind', 'url'),
                 'an older CSS class reads as the URL')
  end

  test 'an item with children is still not deleted on its own; moving its children first is fine' do
    call(:delete, "/menu_items/#{@shop.id}")
    assert_equal 403, response.status
    assert MenuItem.exists?(@shop.id)

    call(:patch, '/menu_items/tree', { group: @main.id, nodes: [{ id: @mugs.id, parent_id: nil, position: 0 }] })
    assert_response :success
    call(:delete, "/menu_items/#{@shop.id}")
    assert_equal 204, response.status
  end
end
