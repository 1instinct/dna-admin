require 'test_helper'

# The claims behind the unavailable-products filter, checked exhaustively rather than by example:
# the scope agrees with Product#available?, no storefront include chain reaches a hidden product,
# and only a live admin token lifts the filter.
class HiddenProductsContractTest < ActionDispatch::IntegrationTest
  setup do
    Spree::StockLocation.create!(name: "Main #{SecureRandom.hex(2)}", propagate_all_variants: true, backorderable_default: false, active: true)
    build_catalog
    @visible.master.stock_items.each { |item| item.set_count_on_hand(10) }
  end

  # --- the scope --------------------------------------------------------------------------

  test 'publicly_visible agrees with available? at every boundary, in any time zone' do
    product = media_product(name: 'Boundary')
    %w[UTC Pacific/Auckland America/Los_Angeles].each do |zone|
      Time.use_zone(zone) do
        freeze_time do
          now = Time.current
          moments = [nil, now - 1.day, now - 1.second, now, now + 1.second, now + 1.day]
          moments.product(moments, [nil, now]).each do |available_on, discontinue_on, deleted_at|
            product.update_columns(available_on: available_on, discontinue_on: discontinue_on, deleted_at: deleted_at)
            expected = Spree::Product.unscoped.find(product.id).available?
            actual = Spree::Product.publicly_visible.exists?(product.id)
            assert_equal expected, actual, "#{zone}: on=#{available_on.inspect} off=#{discontinue_on.inspect} deleted=#{deleted_at.inspect}"
          end
        end
      end
    end
  end

  test 'publicly_visible cannot be undone by with_deleted, and combines with distinct and includes' do
    assert_empty Spree::Product.publicly_visible.with_deleted.where(id: hidden_ids)
    assert_empty Spree::Product.with_deleted.publicly_visible.where(id: hidden_ids)
    assert_equal [@visible.id], Spree::Product.publicly_visible.includes(:master, :taxons).distinct.pluck(:id)
    assert_equal [@visible.id], @taxon.products.publicly_visible.includes(:master).map(&:id)
  end

  # --- include chains ---------------------------------------------------------------------

  def serializer_for(relationship)
    type = relationship.static_record_type or return
    "Spree::V2::Storefront::#{type.to_s.camelize}Serializer".safe_constantize
  end

  def include_chains(serializer, depth)
    return [] if depth.zero?

    (serializer.relationships_to_serialize || {}).flat_map do |name, relationship|
      nested = serializer_for(relationship)
      [name.to_s] + (nested ? include_chains(nested, depth - 1).map { |chain| "#{name}.#{chain}" } : [])
    end
  end

  def product_ids_in(node)
    case node
    when Hash
      own = node['type'] == 'product' ? [node['id'].to_i] : []
      own + node.values.flat_map { |value| product_ids_in(value) }
    when Array then node.flat_map { |value| product_ids_in(value) }
    else []
    end
  end

  def assert_chain_clean(path, headers = {})
    get path, headers: headers
    assert_operator response.status, :<, 500, path
    return unless response.status == 200

    assert_nothing_secret
    assert_empty product_ids_in(JSON.parse(response.body)) & hidden_ids, "#{path} lists a hidden product"
  end

  test 'no include chain from a product reaches a hidden product' do
    chains = include_chains(Spree::V2::Storefront::ProductSerializer, 3)
    assert_includes chains, 'taxons.products.taxons'
    chains.each do |chain|
      assert_chain_clean "/api/v2/storefront/products/#{@visible.slug}?include=#{chain}"
      assert_chain_clean "/api/v2/storefront/products?include=#{chain}"
    end
  end

  test 'no include chain from a taxon reaches a hidden product' do
    chains = include_chains(Spree::V2::Storefront::TaxonSerializer, 3)
    assert_includes chains, 'children.products.taxons'
    chains.each do |chain|
      assert_chain_clean "/api/v2/storefront/taxons/#{@taxon.id}?include=#{chain}"
      assert_chain_clean "/api/v2/storefront/taxons?include=#{chain}"
    end
  end

  test 'no include chain from a cart of visible products reaches a hidden product' do
    post '/api/v2/storefront/cart'
    headers = { 'X-Spree-Order-Token' => media_json['data']['attributes']['token'] }
    post '/api/v2/storefront/cart/add_item', params: { variant_id: @visible.master.id, quantity: 1 }, headers: headers
    assert_response :success

    chains = include_chains(Spree::V2::Storefront::CartSerializer, 5).select { |chain| chain.start_with?('variants', 'line_items') }
    assert_includes chains, 'variants.product.taxons.products'
    chains.each { |chain| assert_chain_clean "/api/v2/storefront/cart?include=#{chain}", headers }
  end

  # --- who counts as an admin -------------------------------------------------------------

  def admin_bearer
    token = Doorkeeper.config.access_token_model.create!(resource_owner_id: @admin.id, expires_in: 3600, scopes: '')
    plaintext = token.respond_to?(:plaintext_token) && token.plaintext_token ? token.plaintext_token : token.token
    [token, { 'Authorization' => "Bearer #{plaintext}" }]
  end

  def admin_paths
    ["/api/v2/storefront/products/#{@null_on.slug}", "/api/v2/storefront/taxons/#{@taxon.id}?include=products",
     "/api/v1/variants/#{@null_on.master.id}.json", "/api/v1/products/#{@null_on.slug}/images.json"]
  end

  # On v2 Spree renders the 401 and carries on, so the action then fails with a DoubleRenderError
  # (a 500 in production). That's Spree's behavior for any stale token; here it must only not leak.
  def assert_stale_token_refused(headers)
    admin_paths.each do |path|
      begin
        get path, headers: headers
      rescue AbstractController::DoubleRenderError
        next
      end
      assert_nothing_secret
      refute_includes [200, 201], response.status, path
    end
  end

  test 'an expired or revoked admin token lifts nothing' do
    @admin = api_user(admin: true)
    expired, expired_headers = admin_bearer
    expired.update_columns(created_at: 2.days.ago)
    assert_stale_token_refused(expired_headers)

    revoked, revoked_headers = admin_bearer
    revoked.revoke
    assert_stale_token_refused(revoked_headers)
  end

  test 'a customer token wins over an admin api key, and the v2 api does not read api keys at all' do
    @admin = api_user(admin: true)
    customer = api_user

    get "/api/v1/variants/#{@null_on.master.id}.json", headers: oauth(customer).merge(api_key(@admin))
    assert_hidden_404

    get "/api/v2/storefront/products/#{@null_on.slug}", headers: api_key(@admin)
    assert_hidden_404
    get "/api/v2/storefront/products/#{@null_on.slug}?token=#{@admin.spree_api_key}"
    assert_hidden_404

    get "/api/v1/variants/#{@null_on.master.id}.json?admin=true&roles[]=admin", headers: api_key(customer)
    assert_hidden_404
  end
end
