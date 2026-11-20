require 'test_helper'

# The app's own endpoints that show a product: favorites, public profiles, live streams, and
# the HTML storefront that spree_frontend mounts on this host.
class HiddenProductsCustomEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    build_catalog
    # The favorites list renders attachment.url, which the test disk service can't build without a host.
    Spree::Image.destroy_all
    @customer = api_user
    @admin = api_user(admin: true)
  end

  def customer
    api_key(@customer)
  end

  # --- favorites --------------------------------------------------------------------------

  test 'a hidden variant cannot be favorited' do
    post '/api/v1/favorites/toggle.json', params: { variant_id: @null_on.master.id }, headers: customer
    assert_equal 404, media_json['response_code'] || response.status
    assert_equal 0, @customer.favorites.count
    assert_nothing_secret
  end

  test 'favorites check does not confirm a hidden variant' do
    get "/api/v1/favorites/check.json?variant_id=#{@null_on.master.id}", headers: customer
    assert_equal 404, media_json['response_code'] || response.status
    assert_nothing_secret
  end

  test 'a favorite made before the product was hidden stays out of the list and can be removed' do
    Favorite.create!(user: @customer, variant: @null_on.master)
    visible = Favorite.create!(user: @customer, variant: @visible.master)

    get '/api/v1/favorites.json', headers: customer
    assert_response :success
    assert_nothing_secret
    assert_equal [visible.id], media_json['data'].map { |f| f['id'] }
    assert_equal 1, media_json['meta']['total_count']

    post '/api/v1/favorites/toggle.json', params: { variant_id: @null_on.master.id }, headers: customer
    assert_response :success
    assert_equal [visible.id], @customer.favorites.reload.map(&:id)
  end

  test 'favorites keep working for visible products' do
    post '/api/v1/favorites/toggle.json', params: { variant_id: @visible.master.id }, headers: customer
    assert_response :success
    get '/api/v1/favorites.json', headers: customer
    assert_equal [@visible.master.id], media_json['data'].map { |f| f['variant']['id'] }
    get "/api/v1/favorites/check.json?variant_id=#{@visible.master.id}", headers: customer
    assert_equal true, media_json['is_favorited']
  end

  test "an admin's own favorites keep hidden products" do
    Favorite.create!(user: @admin, variant: @null_on.master)
    get '/api/v1/favorites.json', headers: api_key(@admin)
    assert_equal [@null_on.id], media_json['data'].map { |f| f['variant']['product']['id'] }
  end

  # --- public profile ---------------------------------------------------------------------

  test 'a public profile does not list a hidden favorite' do
    Favorite.create!(user: @customer, variant: @null_on.master, is_public: true)
    Favorite.create!(user: @customer, variant: @discontinued.master, is_public: true)
    Favorite.create!(user: @customer, variant: @visible.master, is_public: true)

    get "/api/v1/users/#{@customer.id}/profile.json"
    assert_response :success
    assert_nothing_secret
    assert_includes response.body, @visible.slug
  end

  # --- live streams -----------------------------------------------------------------------

  test 'a live stream lists only available product ids, to anyone but an admin' do
    stream = LiveStream.create!(title: 'Stream', actor: @admin, products: [@visible, @null_on, @future, @discontinued])

    [["/api/v1/live_stream/#{stream.id}.json", ->(json) { json['response_data']['product_ids'] }],
     ['/api/v1/live_stream.json', ->(json) { json['response_data'].first['product_ids'] }]].each do |path, ids|
      get path, headers: customer
      assert_response :success, path
      assert_equal [@visible.id], ids.call(media_json), path

      get path, headers: api_key(@admin)
      assert_response :success, path
      assert_empty [@visible.id, @null_on.id, @future.id, @discontinued.id] - ids.call(media_json), path
    end
  end

  # --- spree_frontend on this host --------------------------------------------------------

  test 'the HTML storefront shows nobody a hidden product' do
    ["/products/#{@null_on.slug}", "/products/#{@null_on.id}", "/products/#{@null_on.slug}/related",
     '/products', "/t/#{@taxon.permalink}", "/product_carousel/#{@taxon.id}"].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, 'new_spree_user', 'anonymous visitors get the login page'
      assert_nothing_secret
    end
  end

  # Behind the login, spree_frontend's ProductsController#load_product looks products up in
  # Product.active for anyone but an admin. Its pages can't render here (no compiled assets), so
  # this pins the lookup, which raises the RecordNotFound that Spree turns into its 404 page.
  test 'the lookup behind the HTML product page finds no hidden product' do
    hidden_products.each_value do |product|
      assert_raises(ActiveRecord::RecordNotFound) { Spree::Product.active('USD').friendly.find(product.slug) }
      assert_raises(ActiveRecord::RecordNotFound) { Spree::Product.active('USD').friendly.find(product.id) }
    end
    assert_equal @visible, Spree::Product.active('USD').friendly.find(@visible.slug)
  end
end
