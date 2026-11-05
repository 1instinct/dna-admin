require 'test_helper'

# A product that isn't available must answer 404 on every v2 storefront path, and must not be
# listed or referenced anywhere. Admins keep seeing everything.
class HiddenProductsStorefrontTest < ActionDispatch::IntegrationTest
  setup { build_catalog }

  def listed_ids(query = '', headers: {})
    get "/api/v2/storefront/products#{query}", headers: headers
    assert_response :success
    assert_nothing_secret if headers.empty?
    media_json['data'].map { |p| p['id'].to_i }
  end

  # --- products#show ----------------------------------------------------------------------

  test 'a visible product still answers by slug and by id' do
    get "/api/v2/storefront/products/#{@visible.slug}?include=images,videos"
    assert_response :success
    assert_equal @visible.id.to_s, media_json['data']['id']
    assert(media_json['included'].any? { |i| i['type'] == 'image' })
    assert(media_json['included'].any? { |i| i['type'] == 'product_video' })

    get "/api/v2/storefront/products/#{@visible.id}"
    assert_response :success
  end

  test 'a product with no price still answers on show, as it did' do
    @visible.master.prices.delete_all
    get "/api/v2/storefront/products/#{@visible.slug}"
    assert_response :success
  end

  test 'a hidden product is 404 by slug and by id' do
    hidden_products.each_value do |product|
      get "/api/v2/storefront/products/#{product.slug}"
      assert_hidden_404
      get "/api/v2/storefront/products/#{product.id}"
      assert_hidden_404
      get "/api/v2/storefront/products/#{product.id}?include=images,videos,variants,taxons"
      assert_hidden_404
    end
  end

  test 'a hidden product is 404 by an id with trailing text' do
    get "/api/v2/storefront/products/#{@null_on.id}-anything"
    assert_hidden_404
  end

  test 'a hidden product is 404 by an old slug' do
    old_slug = @null_on.slug
    @null_on.update!(slug: 'secret-null-renamed')
    assert Spree::Product.friendly.exists?(old_slug), 'the old slug is in the FriendlyId history'
    get "/api/v2/storefront/products/#{old_slug}"
    assert_hidden_404
    get '/api/v2/storefront/products/secret-null-renamed'
    assert_hidden_404
  end

  test 'a deleted product is 404, also when asking for deleted products' do
    get "/api/v2/storefront/products/#{@deleted_id}?filter[show_deleted]=1"
    assert_hidden_404
  end

  test 'publishing a hidden product makes it reachable' do
    @null_on.update!(available_on: 1.minute.ago)
    get "/api/v2/storefront/products/#{@null_on.slug}"
    assert_response :success
    get '/api/v2/storefront/products'
    assert_includes media_json['data'].map { |p| p['id'].to_i }, @null_on.id
  end

  test 'a product discontinued from a future date is still visible until then' do
    @visible.update!(discontinue_on: 1.week.from_now)
    get "/api/v2/storefront/products/#{@visible.slug}"
    assert_response :success
    assert_includes listed_ids, @visible.id
  end

  # --- products#index ---------------------------------------------------------------------

  test 'no filter on the listing brings a hidden product back' do
    ids = hidden_ids.join(',')
    {
      'none' => '',
      'ids' => "?filter[ids]=#{ids}",
      'skus' => '?filter[skus]=SECRET-NULL-SKU,SECRET-FUTURE-SKU,SECRET-DISCONTINUED-SKU,SECRET-DELETED-SKU',
      'name' => '?filter[name]=Secret',
      'slug' => "?filter[slug]=#{@null_on.slug}",
      'taxons' => "?filter[taxons]=#{@taxon.id}",
      'concat_taxons' => "?filter[concat_taxons]=#{@taxon.id}",
      'show_deleted' => '?filter[show_deleted]=1',
      'show_discontinued' => '?filter[show_discontinued]=1',
      'both' => '?filter[show_deleted]=1&filter[show_discontinued]=1',
      'ids and both' => "?filter[ids]=#{ids}&filter[show_deleted]=1&filter[show_discontinued]=1",
      'taxons and both' => "?filter[taxons]=#{@taxon.id}&filter[show_deleted]=true&filter[show_discontinued]=true",
      'name and both' => '?filter[name]=Secret&filter[show_deleted]=1&filter[show_discontinued]=1',
      'sku and both' => '?filter[skus]=SECRET-NULL-SKU&filter[show_deleted]=1&filter[show_discontinued]=1',
      'sort newest' => '?filter[show_discontinued]=1&sort_by=newest-first',
      'sort price' => '?filter[show_discontinued]=1&sort_by=price-low-to-high',
      'sort default' => "?filter[taxons]=#{@taxon.id}&filter[show_discontinued]=1&sort_by=default"
    }.each do |label, query|
      found = listed_ids(query)
      assert_empty found & hidden_ids, "filter #{label} listed #{found & hidden_ids}"
    end
  end

  test 'option filters do not bring a hidden product back' do
    color = Spree::OptionType.create!(name: 'hidden-color', presentation: 'Color')
    black = color.option_values.create!(name: 'black', presentation: 'Black')
    @null_on.option_types << color
    variant = @null_on.variants.create!(sku: 'SECRET-BLACK', price: 5, option_values: [black])
    assert variant.persisted?

    ['?filter[options][hidden-color]=black&filter[show_discontinued]=1',
     "?filter[option_value_ids][]=#{black.id}&filter[show_discontinued]=1",
     '?filter[skus]=SECRET-BLACK&filter[show_discontinued]=1'].each do |query|
      assert_not_includes listed_ids(query), @null_on.id, query
    end
  end

  test 'filters still work for visible products' do
    assert_equal [@visible.id], listed_ids("?filter[ids]=#{@visible.id}")
    assert_equal [@visible.id], listed_ids('?filter[skus]=VISIBLE-SKU')
    assert_equal [@visible.id], listed_ids('?filter[name]=Visible')
    assert_equal [@visible.id], listed_ids("?filter[taxons]=#{@taxon.id}")
  end

  test 'a signed-in customer gets the same answers as the public' do
    headers = oauth(api_user)
    get "/api/v2/storefront/products/#{@null_on.slug}", headers: headers
    assert_hidden_404
    get '/api/v2/storefront/products?filter[show_deleted]=1&filter[show_discontinued]=1', headers: headers
    assert_response :success
    assert_nothing_secret
    get "/api/v2/storefront/taxons/#{@taxon.permalink}?include=products", headers: headers
    assert_response :success
    assert_nothing_secret
  end

  # --- taxons -----------------------------------------------------------------------------

  def assert_taxon_clean(taxon_json)
    ids = taxon_json['relationships']['products']['data'].map { |p| p['id'].to_i }
    assert_empty ids & hidden_ids, "taxon relationship lists #{ids & hidden_ids}"
    ids
  end

  test 'a taxon lists only available products in its relationship' do
    get "/api/v2/storefront/taxons/#{@taxon.permalink}"
    assert_response :success
    assert_equal [@visible.id], assert_taxon_clean(media_json['data'])
    assert_nothing_secret

    get "/api/v2/storefront/taxons/#{@taxon.id}"
    assert_response :success
    assert_equal [@visible.id], assert_taxon_clean(media_json['data'])
  end

  test 'include=products and deeper includes expose only available products' do
    %w[products products.images products.videos products.variants products.variants.images
       products.product_properties products.taxons].each do |includes|
      get "/api/v2/storefront/taxons/#{@taxon.permalink}?include=#{includes}"
      assert_response :success, includes
      assert_taxon_clean(media_json['data'])
      assert_nothing_secret
      products = media_json['included'].select { |i| i['type'] == 'product' }
      assert_equal [@visible.id], products.map { |p| p['id'].to_i }, includes
    end

    master_ids = hidden_products.values.map { |p| p.master.id.to_s }
    get "/api/v2/storefront/taxons/#{@taxon.permalink}?include=products.variants,products.images,products.default_variant"
    included = media_json['included']
    assert_empty included.select { |i| i['type'] == 'variant' }.map { |v| v['id'] } & master_ids
    hidden_image_ids = hidden_products.values.flat_map { |p| p.master.images.map { |i| i.id.to_s } }
    assert_empty included.select { |i| i['type'] == 'image' }.map { |v| v['id'] } & hidden_image_ids
  end

  test 'taxon index and nested taxons list only available products' do
    get '/api/v2/storefront/taxons?include=products,children.products,parent.products,taxonomy.root.products'
    assert_response :success
    assert_nothing_secret
    media_json['data'].each { |taxon| assert_taxon_clean(taxon) }
    (media_json['included'] || []).select { |i| i['type'] == 'taxon' }.each { |taxon| assert_taxon_clean(taxon) }

    get "/api/v2/storefront/taxons/#{@taxon.taxonomy.root.id}?include=children.products"
    assert_response :success
    assert_nothing_secret
  end

  test 'a visible product cannot reach a hidden one through its taxons' do
    get "/api/v2/storefront/products/#{@visible.slug}?include=taxons.products.images"
    assert_response :success
    assert_nothing_secret
    media_json['included'].select { |i| i['type'] == 'taxon' }.each { |taxon| assert_taxon_clean(taxon) }

    get '/api/v2/storefront/products?include=taxons.products.variants'
    assert_response :success
    assert_nothing_secret
  end

  # --- admins -----------------------------------------------------------------------------

  test 'an admin token still reaches hidden products' do
    headers = oauth(api_user(admin: true))
    hidden_products.each_value do |product|
      get "/api/v2/storefront/products/#{product.slug}", headers: headers
      assert_response :success
      assert_equal product.id.to_s, media_json['data']['id']
    end

    assert_includes listed_ids('?filter[show_discontinued]=1', headers: headers), @null_on.id
    get "/api/v2/storefront/taxons/#{@taxon.permalink}", headers: headers
    assert_includes media_json['data']['relationships']['products']['data'].map { |p| p['id'].to_i }, @null_on.id
  end
end
