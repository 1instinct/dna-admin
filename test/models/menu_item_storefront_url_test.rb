require 'test_helper'

# Typed menu links resolve to storefront paths, so a storefront reading `url` keeps working when an
# item links to a product, taxon or page instead of a typed URL.
class MenuItemStorefrontUrlTest < ActiveSupport::TestCase
  setup do
    @location = MenuLocation.create!(title: 'Main', location: 'header', is_visible: true)
    @saved = ENV.to_h.slice('MENU_PRODUCT_PATH', 'MENU_TAXON_PATH', 'MENU_PAGE_PATH')
  end

  teardown do
    %w[MENU_PRODUCT_PATH MENU_TAXON_PATH MENU_PAGE_PATH].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) }
  end

  def make_product(name = "Product #{SecureRandom.hex(3)}")
    Spree::Product.create!(name: name, price: 10, shipping_category: Spree::ShippingCategory.first_or_create!(name: 'Default'))
  end

  def make_taxon(name)
    taxonomy = Spree::Taxonomy.create!(name: "Categories #{SecureRandom.hex(3)}")
    Spree::Taxon.create!(name: name, taxonomy: taxonomy, parent: taxonomy.root)
  end

  def item(attrs)
    MenuItem.create!({ name: 'Item', menu_location: @location }.merge(attrs))
  end

  test 'a URL link, or an older CSS class, is its url' do
    assert_equal '/about', item(url: '/about', item_class: 'url').storefront_url
    assert_equal '/sale', item(url: '/sale', item_class: 'highlight').storefront_url
  end

  test 'a product link follows the product slug' do
    product = make_product('Canvas Tote')
    link = item(item_class: 'product', item_id: product.id.to_s)
    assert_equal "/#{product.slug}", link.storefront_url
    product.update!(slug: 'tote-bag')
    assert_equal '/tote-bag', link.reload.storefront_url
  end

  test 'a taxon link opens browse filtered by its name' do
    taxon = make_taxon('Bags & Totes')
    assert_equal '/browse?categories=Bags%20%26%20Totes', item(item_class: 'taxon', item_id: taxon.id.to_s).storefront_url
  end

  test 'a page link uses its slug or foreign link' do
    skip 'no Spree::Page here' unless defined?(Spree::Page)
    page = Spree::Page.create!(title: 'Shipping', slug: '/shipping', body: 'x')
    assert_equal '/shipping', item(item_class: 'page', item_id: page.id.to_s).storefront_url
    page.update!(foreign_link: 'https://help.example.com')
    assert_equal 'https://help.example.com', item(item_class: 'page', item_id: page.id.to_s).storefront_url
  end

  test 'storefronts with other routes set the pattern' do
    ENV['MENU_PRODUCT_PATH'] = '/products/%{slug}'
    product = make_product
    assert_equal "/products/#{product.slug}", item(item_class: 'product', item_id: product.id.to_s).storefront_url
  end

  test 'a missing record falls back to the stored url' do
    assert_equal '/old', item(item_class: 'product', item_id: '999999', url: '/old').storefront_url
    assert_equal '', item(item_class: 'product', item_id: '999999').storefront_url
  end

  test 'the menu API serves the resolved url' do
    product = make_product
    item(item_class: 'product', item_id: product.id.to_s)
    get_json = ActionDispatch::Integration::Session.new(Rails.application)
    get_json.get '/api/v1/menu_items.json', params: { menu_location_id: @location.id }
    body = JSON.parse(get_json.response.body)
    urls = body.dig('response_data', 'menu_location_listing', 0, 'menu_item_listing').map { |i| i['url'] }
    assert_includes urls, "/#{product.slug}"
  end
end
