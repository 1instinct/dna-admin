require 'test_helper'

# The v1 API, called with no credentials, with a customer's key, as a guest holding an order
# token, and as an admin (the admin's taxon drag-sort and the seed script use it).
class HiddenProductsV1Test < ActionDispatch::IntegrationTest
  setup do
    build_catalog
    @customer = api_user
    @admin = api_user(admin: true)
  end

  def customer
    api_key(@customer)
  end

  def admin
    api_key(@admin)
  end

  def hidden_paths(product)
    variant = product.master
    image = variant.images.first
    [
      "/api/v1/products/#{product.slug}.json",
      "/api/v1/products/#{product.id}.json",
      "/api/v1/products/#{product.slug}/variants.json",
      "/api/v1/products/#{product.id}/variants.json",
      "/api/v1/products/#{product.slug}/variants/#{variant.id}.json",
      "/api/v1/products/#{product.slug}/images.json",
      "/api/v1/products/#{product.slug}/images/#{image.id}.json",
      "/api/v1/products/#{product.slug}/product_properties.json",
      "/api/v1/products/#{product.slug}/product_properties/colour.json",
      "/api/v1/variants/#{variant.id}.json",
      "/api/v1/variants/#{variant.id}/images.json",
      "/api/v1/variants/#{variant.id}/images/#{image.id}.json"
    ]
  end

  test 'nobody signed in gets a 401 on the catalog' do
    ['/api/v1/products.json', "/api/v1/products/#{@null_on.slug}.json", "/api/v1/variants/#{@null_on.master.id}.json",
     '/api/v1/variants.json', "/api/v1/taxons/products.json?id=#{@taxon.id}",
     "/api/v1/products/#{@null_on.slug}/images.json"].each do |path|
      get path
      assert_response :unauthorized, path
      assert_nothing_secret
    end
  end

  test 'a customer gets a 404 for every path of a hidden product' do
    hidden_products.each_value do |product|
      hidden_paths(product).each do |path|
        get path, headers: customer
        assert_hidden_404
      end
    end
  end

  test 'a guest holding an order token gets a 404 as well' do
    post '/api/v2/storefront/cart'
    attributes = media_json['data']['attributes']
    query = "?order_token=#{attributes['token']}&order_id=#{attributes['number']}"
    hidden_paths(@null_on).each do |path|
      get "#{path}#{query}"
      assert_hidden_404
    end
    get "/api/v1/variants.json#{query}"
    assert_response :success
    assert_nothing_secret
  end

  test 'a customer cannot reach a hidden product by an old slug' do
    old_slug = @null_on.slug
    @null_on.update!(slug: 'secret-null-renamed')
    ["/api/v1/products/#{old_slug}.json", "/api/v1/products/#{old_slug}/variants.json",
     "/api/v1/products/#{old_slug}/images.json", "/api/v1/products/#{old_slug}/product_properties.json"].each do |path|
      get path, headers: customer
      assert_hidden_404
    end
  end

  test 'listings show a customer only available products' do
    variant_ids = hidden_products.values.map { |p| p.master.id }.join(',')
    ['/api/v1/products.json', "/api/v1/products.json?ids=#{hidden_ids.join(',')}",
     '/api/v1/products.json?q[name_cont]=Secret', '/api/v1/products.json?show_deleted=1&show_discontinued=1',
     '/api/v1/variants.json', '/api/v1/variants.json?per_page=100', '/api/v1/variants.json?show_deleted=1',
     "/api/v1/variants.json?q[id_in]=#{variant_ids}", '/api/v1/variants.json?q[sku_cont]=SECRET',
     '/api/v1/variants.json?q[product_name_or_sku_cont]=Secret',
     "/api/v1/taxons/products.json?id=#{@taxon.id}", "/api/v1/taxons/products.json?id=#{@taxon.id}&per_page=500",
     "/api/v1/taxons/products.json?id=#{@taxon.id}&q[name_cont]=Secret",
     '/api/v1/taxons.json', "/api/v1/taxonomies/#{@taxon.taxonomy_id}/taxons/#{@taxon.id}.json",
     '/api/v1/taxonomies.json', '/api/v1/properties.json', '/api/v1/option_types.json'].each do |path|
      get path, headers: customer
      assert_response :success, path
      assert_nothing_secret
    end
  end

  test 'listings keep showing a customer the available products' do
    get '/api/v1/products.json', headers: customer
    assert_equal [@visible.id], media_json['products'].map { |p| p['id'] }

    get "/api/v1/products/#{@visible.slug}.json", headers: customer
    assert_response :success

    get '/api/v1/variants.json', headers: customer
    assert_equal [@visible.master.id], media_json['variants'].map { |v| v['id'] }

    get "/api/v1/variants/#{@visible.master.id}.json", headers: customer
    assert_response :success

    get "/api/v1/products/#{@visible.slug}/variants.json", headers: customer
    assert_response :success
    assert_equal [@visible.master.id], media_json['variants'].map { |v| v['id'] }

    get "/api/v1/taxons/products.json?id=#{@taxon.id}", headers: customer
    assert_response :success
    assert_equal [@visible.id], media_json['products'].map { |p| p['id'] }

    get "/api/v1/products/#{@visible.slug}/product_properties.json", headers: customer
    assert_response :success
    get "/api/v1/products/#{@visible.slug}/images.json", headers: customer
    assert_response :success
  end

  test 'a customer cannot change a classification or read stock' do
    put '/api/v1/classifications.json', params: { product_id: @null_on.id, taxon_id: @taxon.id, position: 0 }, headers: customer
    assert_response :unauthorized
    get '/api/v1/stock_items.json', headers: customer
    assert_nothing_secret
    get '/api/v1/stock_locations.json', headers: customer
    assert_nothing_secret
  end

  # --- admins -----------------------------------------------------------------------------

  test 'an admin reaches every path of a hidden product' do
    hidden_products.each_value do |product|
      hidden_paths(product).each do |path|
        # Spree's own admin branch leaves discontinued products out unless asked for them.
        path += '?show_discontinued=1' if product == @discontinued
        get path, headers: admin
        assert_response :success, path
      end
    end
  end

  test 'an admin sees hidden products in listings' do
    get '/api/v1/variants.json?per_page=100', headers: admin
    assert_includes media_json['variants'].map { |v| v['id'] }, @null_on.master.id

    get "/api/v1/products.json?ids=#{@null_on.id}", headers: admin
    assert_equal [@null_on.id], media_json['products'].map { |p| p['id'] }

    get "/api/v1/products/#{@discontinued.slug}.json?show_discontinued=1", headers: admin
    assert_response :success
  end

  test 'the admin taxon sort still lists hidden products and can move them' do
    get "/api/v1/taxons/products.json?id=#{@taxon.id}", headers: admin
    assert_response :success
    assert_includes media_json['products'].map { |p| p['id'] }, @null_on.id

    put '/api/v1/classifications.json', params: { product_id: @null_on.id, taxon_id: @taxon.id, position: 0 }, headers: admin
    assert_response :success
    assert_equal 1, Spree::Classification.find_by!(product: @null_on, taxon: @taxon).position
  end

  test 'an admin can create and update products as the seed does, including a hidden one' do
    category = Spree::ShippingCategory.first
    post '/api/v1/products.json', params: { product: { name: 'Seeded', price: 3, shipping_category_id: category.id } }, headers: admin
    assert_response :created

    put "/api/v1/products/#{@null_on.slug}.json", params: { product: { description: 'edited' } }, headers: admin
    assert_response :success
    assert_equal 'edited', @null_on.reload.description
  end
end
