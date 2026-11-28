require 'test_helper'

# The Rails admin's menu builder (/admin/menus, Spree::Admin::MenusController over MenuBuilder):
# location tabs, the nested tree, moves with the app's rules (SpreeAdminNative::Tree), inline add,
# edit, the children rule on delete, and admin-only JSON endpoints.
class Spree::Admin::MenusControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ChatTestHelper

  setup do
    @admin = chat_admin(email: 'menus-admin@example.com')
    login_as(@admin, scope: :spree_user)
    @main = MenuLocation.create!(title: 'Main', location: 'header', is_visible: true)
    @footer = MenuLocation.create!(title: 'Footer', location: 'footer', is_visible: true)
    @shop = MenuItem.create!(name: 'Shop', menu_location: @main, url: '/shop', item_class: 'url')
    @mugs = MenuItem.create!(name: 'Mugs', menu_location: @main, parent: @shop, url: '/mugs')
    @cups = MenuItem.create!(name: 'Cups', menu_location: @main, parent: @mugs, url: '/cups')
    @about = MenuItem.create!(name: 'About', menu_location: @main, url: '/about')
    @legal = MenuItem.create!(name: 'Legal', menu_location: @footer, url: '/legal')
  end

  teardown { Warden.test_reset! }

  def json(method, path, body = nil)
    send(method, path, params: body&.to_json, headers: { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' })
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def names(nodes)
    nodes.map { |n| n['children'].any? ? { n['name'] => names(n['children']) } : n['name'] }
  end

  def tree_names(location = @main)
    names(json(:get, "/admin/menus/#{location.id}/tree")['data'])
  end

  test 'the page shows a tab per location and the builder for the chosen one' do
    get '/admin/menus'
    assert_response :success
    assert_select '.nav-tabs a.nav-link', text: /Main/
    assert_select '.nav-tabs a.nav-link', text: /Footer/
    assert_select '.nav-tabs a.nav-link.active[aria-current=page]', text: /Main/
    assert_select '#menu-builder[data-tree-url=?]', "/admin/menus/#{@main.id}/tree"
    assert_select '#menu-item-modal label[for=menu-item-name]', text: 'Name'

    get "/admin/menus?location=#{@footer.id}"
    assert_select '.nav-tabs a.nav-link.active', text: /Footer/
  end

  test 'with no locations the page offers to add one' do
    MenuItem.unscoped.delete_all
    MenuLocation.delete_all
    get '/admin/menus'
    assert_response :success
    assert_select 'button[data-target="#menu-location-new-modal"]', text: 'Add a menu'
  end

  test 'GET tree nests the location with storefront URLs and typed links' do
    product = media_product(name: 'Blue Mug')
    product.update!(slug: 'blue-mug')
    @about.update_columns(item_class: 'product', item_id: product.id.to_s, url: nil)

    body = json(:get, "/admin/menus/#{@main.id}/tree")
    assert_response :success
    assert_equal [{ 'Shop' => [{ 'Mugs' => ['Cups'] }] }, 'About'], names(body['data'])
    shop, about = body['data']
    assert_equal '/shop', shop['url']
    assert_equal({ 'kind' => 'url', 'url' => '/shop' }, shop['link'])
    assert_equal '/blue-mug', about['url'], 'a product link resolves to its storefront path'
    assert_equal({ 'kind' => 'product', 'id' => product.id.to_s, 'title' => 'Blue Mug' }, about['link'])
    assert_equal 'Main', body.dig('meta', 'location', 'title')
  end

  test 'PATCH tree reorders and renumbers positions' do
    body = json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @about.id, parent_id: nil, position: 0 }])
    assert_response :success
    assert_equal ['About', { 'Shop' => [{ 'Mugs' => ['Cups'] }] }], names(body['data'])
    assert_equal [0, 1], [@about.reload.position, @shop.reload.position]
  end

  test 'PATCH tree nests and un-nests items' do
    json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @about.id, parent_id: @shop.id, position: 0 }])
    assert_response :success
    assert_equal [{ 'Shop' => ['About', { 'Mugs' => ['Cups'] }] }], tree_names
    assert_equal @shop.id, @about.reload.parent_id

    json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @cups.id, parent_id: nil, position: 1 }])
    assert_equal [{ 'Shop' => %w[About Mugs] }, 'Cups'], tree_names
  end

  test 'PATCH tree refuses a cycle and leaves the tree unchanged' do
    body = json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @shop.id, parent_id: @cups.id, position: 0 }])
    assert_response :unprocessable_entity
    assert_equal 'cycle', body.dig('error', 'code')
    assert_match(/can't move under one of its own items/, body.dig('error', 'message'))
    assert_equal [{ 'Shop' => [{ 'Mugs' => ['Cups'] }] }, 'About'], tree_names
  end

  test 'PATCH tree refuses items and parents from another location' do
    body = json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @legal.id, parent_id: nil, position: 0 }])
    assert_response :unprocessable_entity
    assert_equal 'outside_group', body.dig('error', 'code')

    json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @about.id, parent_id: @legal.id, position: 0 }])
    assert_response :unprocessable_entity
    assert_nil @about.reload.parent_id
  end

  test 'POST items adds at the end, inside a parent or right after a sibling' do
    body = json(:post, "/admin/menus/#{@main.id}/items", menu_item: { name: 'Contact' })
    assert_response :created
    assert_equal 'Contact', body.dig('data', 'name')
    assert_equal ['Contact'], body['tree'].map { |n| n['name'] } - %w[Shop About]
    assert_equal 'Contact', body['tree'].last['name']

    json(:post, "/admin/menus/#{@main.id}/items", menu_item: { name: 'Plates', parent_id: @shop.id })
    json(:post, "/admin/menus/#{@main.id}/items", menu_item: { name: 'Sale' }, after_id: @shop.id)
    assert_equal [{ 'Shop' => [{ 'Mugs' => ['Cups'] }, 'Plates'] }, 'Sale', 'About', 'Contact'], tree_names
    assert MenuItem.find_by(name: 'Sale').is_visible
  end

  test 'POST items refuses a parent from another location and a blank name' do
    body = json(:post, "/admin/menus/#{@main.id}/items", menu_item: { name: 'Stray', parent_id: @legal.id })
    assert_response :unprocessable_entity
    assert_equal 'outside_group', body.dig('error', 'code')

    body = json(:post, "/admin/menus/#{@main.id}/items", menu_item: { name: ' ' })
    assert_response :unprocessable_entity
    assert_match(/Name can't be blank/, body.dig('error', 'message'))
    assert_nil MenuItem.find_by(name: 'Stray')
  end

  test 'PATCH items saves the name, link, target and visibility' do
    taxonomy = Spree::Taxonomy.create!(name: 'Categories')
    taxon = Spree::Taxon.create!(name: 'Kitchen', taxonomy: taxonomy, parent: taxonomy.root)
    body = json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}",
                menu_item: { name: 'Kitchen', link: { kind: 'taxon', id: taxon.id }, item_target: '_blank', is_visible: false })
    assert_response :success
    assert_equal({ 'kind' => 'taxon', 'id' => taxon.id.to_s, 'title' => taxon.pretty_name }, body.dig('data', 'link'))
    assert_equal '/browse?categories=Kitchen', body.dig('data', 'url')
    @about.reload
    assert_equal ['Kitchen', 'taxon', taxon.id.to_s, nil, '_blank', false],
                 [@about.name, @about.item_class, @about.item_id, @about.url, @about.item_target, @about.is_visible]

    json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}", menu_item: { link: { kind: 'url', url: '/kitchen' } })
    assert_equal ['url', '/kitchen', nil], [@about.reload.item_class, @about.url, @about.item_id]

    json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}", menu_item: { link: { kind: '' } })
    assert_equal [nil, nil, nil], [@about.reload.item_class, @about.url, @about.item_id]
  end

  test 'PATCH items refuses unknown link kinds, missing records and bad targets' do
    body = json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}", menu_item: { link: { kind: 'video', id: 1 } })
    assert_response :unprocessable_entity
    assert_match(/Link kind must be one of url, product, taxon/, body.dig('error', 'message'))

    body = json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}", menu_item: { link: { kind: 'product', id: 0 } })
    assert_response :unprocessable_entity
    assert_equal "That product doesn't exist.", body.dig('error', 'message')

    json(:patch, "/admin/menus/#{@main.id}/items/#{@about.id}", menu_item: { item_target: 'popup' })
    assert_response :unprocessable_entity
    assert_equal '/about', @about.reload.url

    json(:patch, "/admin/menus/#{@main.id}/items/#{@legal.id}", menu_item: { name: 'Elsewhere' })
    assert_response :not_found
  end

  test 'DELETE items deletes a leaf, and an item with children only with them' do
    body = json(:delete, "/admin/menus/#{@main.id}/items/#{@about.id}")
    assert_response :success
    assert_equal 1, body['deleted']
    assert_nil MenuItem.find_by(id: @about.id)

    body = json(:delete, "/admin/menus/#{@main.id}/items/#{@shop.id}")
    assert_response :unprocessable_entity
    assert_equal 'has_children', body.dig('error', 'code')
    assert_match(/Shop has 2 child items/, body.dig('error', 'message'))
    assert MenuItem.exists?(@cups.id)

    body = json(:delete, "/admin/menus/#{@main.id}/items/#{@shop.id}?with_children=1")
    assert_response :success
    assert_equal 3, body['deleted']
    assert_empty body['tree']
    assert_equal 0, MenuItem.where(menu_location_id: @main.id).count
    assert MenuItem.exists?(@legal.id)
  end

  test 'locations are added, renamed and deleted with their items' do
    post '/admin/menus/locations', params: { menu_location: { title: 'Sidebar', location: 'sidebar', is_visible: '1' } }
    sidebar = MenuLocation.find_by!(title: 'Sidebar')
    assert_redirected_to "/admin/menus?location=#{sidebar.id}"
    assert sidebar.is_visible

    patch "/admin/menus/locations/#{sidebar.id}", params: { menu_location: { title: 'Side', is_visible: '0' } }
    assert_redirected_to "/admin/menus?location=#{sidebar.id}"
    assert_equal ['Side', false], [sidebar.reload.title, sidebar.is_visible]

    delete "/admin/menus/locations/#{@main.id}"
    assert_redirected_to '/admin/menus'
    assert_nil MenuLocation.find_by(id: @main.id)
    assert_equal 0, MenuItem.unscoped.where(menu_location_id: @main.id).count
    assert MenuItem.exists?(@legal.id)
  end

  test 'non-admins are refused, the JSON endpoints with a status' do
    user = Spree.user_class.create!(email: 'shopper@example.com', password: 'password123')
    login_as(user, scope: :spree_user)

    get '/admin/menus'
    assert_redirected_to '/forbidden'
    json(:get, "/admin/menus/#{@main.id}/tree")
    assert_response :forbidden
    json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @about.id, parent_id: nil, position: 0 }])
    assert_response :forbidden
    json(:delete, "/admin/menus/#{@main.id}/items/#{@about.id}")
    assert_response :forbidden
    assert MenuItem.exists?(@about.id)

    logout(:spree_user)
    json(:get, "/admin/menus/#{@main.id}/tree")
    assert_response :unauthorized
  end

  test 'JSON writes need the CSRF token from the page' do
    ActionController::Base.allow_forgery_protection = true
    get '/admin/menus'
    token = css_select('meta[name="csrf-token"]').first['content']

    assert_raises(ActionController::InvalidAuthenticityToken) do
      json(:patch, "/admin/menus/#{@main.id}/tree", nodes: [{ id: @about.id, parent_id: nil, position: 0 }])
    end

    patch "/admin/menus/#{@main.id}/tree", params: { nodes: [{ id: @about.id, parent_id: nil, position: 0 }] }.to_json,
                                           headers: { 'CONTENT_TYPE' => 'application/json', 'X-CSRF-Token' => token }
    assert_response :success
    assert_equal 0, @about.reload.position
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
