require 'test_helper'

# M7 service endpoints for the storefront's AI summarizer: docs/plans/2026-11-26-reviews-api-contract.md,
# "M7 AI summaries". Admin API key (X-Spree-Token) or admin Bearer.
class Spree::Api::V1::Admin::ReviewSummariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @settings = reviews_enable!(ai_summary_enabled: true, ai_summary_min_reviews: 2)
    @product = media_product(name: 'Rib-Knit Wrap Top')
    @service = media_admin
    @service.generate_spree_api_key!
    @headers = { 'X-Spree-Token' => @service.spree_api_key }
  end

  def json
    JSON.parse(response.body)
  end

  def put_summary(body, headers: @headers, product: @product)
    put "/api/v1/admin/review_summaries/#{product.slug}", params: body.is_a?(String) ? body : body.to_json,
                                                          headers: headers.merge('CONTENT_TYPE' => 'application/json')
  end

  def summary_body(**overrides)
    { headline: 'Soft, runs a little small', summary: 'Most buyers love the fabric; a few size up.',
      pros: [{ label: 'Soft fabric', mentions: 12 }], cons: [{ label: 'Runs small', mentions: 3 }],
      fit_consensus: 'runs_small', review_count: 2, model: 'claude-opus-5-5' }.merge(overrides)
  end

  test 'auth: admin API key or admin Bearer; 401 when unresolved; 403 for non-admins' do
    paths = ['/api/v1/admin/review_summaries/stale', "/api/v1/admin/products/#{@product.slug}/reviews_for_summary"]
    customer = create(:user)
    customer.generate_spree_api_key!

    paths.each do |path|
      get path, headers: @headers
      assert_response :success, "admin API key: #{path}"
      get path, headers: auth(@service)
      assert_response :success, "admin Bearer: #{path}"

      get path
      assert_response :unauthorized, "no credentials: #{path}"
      get path, headers: { 'X-Spree-Token' => 'nope' }
      assert_response :unauthorized, "unknown key: #{path}"
      get path, headers: bearer('nope').merge(@headers)
      assert_response :unauthorized, "a bad Bearer is refused even with a good key: #{path}"

      get path, headers: { 'X-Spree-Token' => customer.spree_api_key }
      assert_response :forbidden, "non-admin key (e.g. the storefront's): #{path}"
      assert_equal 'Admin only', json['error']
      get path, headers: auth(customer)
      assert_response :forbidden, "non-admin Bearer: #{path}"
    end

    put_summary(summary_body, headers: {})
    assert_response :unauthorized
    put_summary(summary_body, headers: { 'X-Spree-Token' => customer.spree_api_key })
    assert_response :forbidden
    assert_nil retail_stat(@product).ai_summary
  end

  test 'stale lists products that need a summary' do
    published_reviews(@product, 2)
    summarized = media_product(name: 'Slip Skirt')
    published_reviews(summarized, 2)
    store_ai_summary(summarized, review_count: 2, generated_at: Time.zone.parse('2026-10-01'))

    get '/api/v1/admin/review_summaries/stale', headers: @headers
    assert_response :success
    assert_equal [{ 'product_id' => @product.id, 'slug' => @product.slug, 'name' => 'Rib-Knit Wrap Top', 'reviews_count' => 2,
                    'summarized_count' => nil, 'generated_at' => nil },
                  { 'product_id' => summarized.id, 'slug' => summarized.slug, 'name' => 'Slip Skirt', 'reviews_count' => 2,
                    'summarized_count' => 2, 'generated_at' => '2026-10-01T00:00:00Z' }], json['data']

    get '/api/v1/admin/review_summaries/stale', params: { limit: 1 }, headers: @headers
    assert_equal [@product.id], json['data'].map { |row| row['product_id'] }
  end

  test 'stale is empty while AI summaries are off' do
    published_reviews(@product, 2)
    @settings.update!(ai_summary_enabled: false)
    get '/api/v1/admin/review_summaries/stale', headers: @headers
    assert_response :success
    assert_equal({ 'data' => [] }, json)
  end

  test 'reviews_for_summary: product, retail stats and written retail reviews' do
    written = published_review(@product, rating: 4, body: 'Lovely')
    published_review(@product, rating: 2, body: nil)
    published_review(@product, rating: 1, body: 'Trade', channel: 'wholesale')
    @product.update!(description: '<p>Soft <em>knit</em></p>')

    get "/api/v1/admin/products/#{@product.id}/reviews_for_summary", headers: @headers
    assert_response :success
    assert_equal({ 'id' => @product.id, 'slug' => @product.slug, 'name' => 'Rib-Knit Wrap Top', 'description' => 'Soft knit' },
                 json['product'])
    assert_equal [2, 1], json.values_at('ratings_count', 'reviews_count')
    assert_equal({ '1' => 0, '2' => 1, '3' => 0, '4' => 1, '5' => 0 }, json['histogram'])
    assert_equal [written.id], json['reviews'].map { |review| review['id'] }
    assert_equal %w[id rating title body variant_label attribute_ratings published_at].sort, json['reviews'].first.keys.sort

    get '/api/v1/admin/products/no-such-product/reviews_for_summary', headers: @headers
    assert_response :not_found
  end

  test 'PUT stores the summary on the retail stat and review_summary shows it' do
    published_reviews(@product, 2)
    Reviews::AiSummaries.request_regeneration!(@product) # no summary yet: a no-op
    put_summary(summary_body(headline: '<script>alert(1)</script><b>Soft</b>, runs a little small'))
    assert_response :success
    ai = json['ai_summary']
    assert_equal 'Soft, runs a little small', ai['headline']
    assert_equal [{ 'label' => 'Soft fabric', 'mentions' => 12 }], ai['pros']
    assert_equal %w[retail 2 claude-opus-5-5], [ai['source_scope'], ai['review_count'].to_s, ai['model']]

    stat = retail_stat(@product)
    assert_equal 2, stat.ai_summary_review_count
    assert_in_delta Time.current, stat.ai_summary_generated_at, 5

    get "/api/v1/products/#{@product.slug}/review_summary"
    public_summary = json['ai_summary']
    assert_equal 'Soft, runs a little small', public_summary['headline']
    assert_equal 'runs_small', public_summary['fit_consensus']
    assert_equal 2, public_summary['review_count']
    assert_equal 'retail', public_summary['source_scope']

    get '/api/v1/admin/review_summaries/stale', headers: @headers
    assert_equal [], json['data'], 'fresh now'
  end

  test 'PUT validation is strict: 422 with fields' do
    put_summary(summary_body(headline: 'x' * 81, pros: Array.new(6) { { label: 'a', mentions: 1 } },
                             cons: [{ label: 'ok', mentions: 0 }], fit_consensus: 'tiny'))
    assert_response :unprocessable_entity
    assert_equal %w[cons[0].mentions fit_consensus headline pros], json['fields'].keys.sort
    assert json['error'].present?

    # Malformed JSON sent as JSON is a 400 from Rails' params parser before the action runs.
    put "/api/v1/admin/review_summaries/#{@product.slug}", params: 'not json', headers: @headers.merge('CONTENT_TYPE' => 'text/plain')
    assert_response :unprocessable_entity
    put_summary('[1, 2]')
    assert_response :unprocessable_entity
    assert_nil retail_stat(@product).ai_summary
  end

  test 'PUT is 503 while AI summaries are off, and 404 for an unknown product' do
    @settings.update!(ai_summary_enabled: false)
    put_summary(summary_body)
    assert_response :service_unavailable
    assert_equal 'not_enabled', json['code']
    assert_nil retail_stat(@product).ai_summary

    @settings.update!(ai_summary_enabled: true)
    put '/api/v1/admin/review_summaries/999999999', params: summary_body.to_json,
                                                    headers: @headers.merge('CONTENT_TYPE' => 'application/json')
    assert_response :not_found
  end

  test 'swagger docs list the endpoints' do
    get '/apidocs'
    assert_response :success
    paths = JSON.parse(response.body)['paths']
    assert paths.key?('/admin/review_summaries/stale')
    assert paths.key?('/admin/products/{product_id}/reviews_for_summary')
    assert paths['/admin/review_summaries/{product_id}'].key?('put')
  end
end
