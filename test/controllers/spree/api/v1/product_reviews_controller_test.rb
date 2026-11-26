require 'test_helper'

# Public review endpoints: docs/plans/2026-11-26-reviews-api-contract.md.
class Spree::Api::V1::ProductReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!(photos_require_approval: false)
    @product = media_product(name: 'Rib-Knit Wrap Top')
    @base = "/api/v1/products/#{@product.slug}"
  end

  def review_by(user = create(:user), **params)
    reviews_order(@product, user: user)
    reviews_submit(@product, user: user, **params).review
  end

  def json
    JSON.parse(response.body)
  end

  def ids
    json['data'].map { |review| review['id'] }
  end

  test 'a product with no reviews has an empty summary' do
    get "#{@base}/review_summary"
    assert_response :success
    assert_equal 'retail', json['scope']
    assert_equal [0.0, 0, 0], json.values_at('average', 'ratings_count', 'reviews_count')
    assert_equal({ '1' => 0, '2' => 0, '3' => 0, '4' => 0, '5' => 0 }, json['histogram'])
    assert_equal [[], [], nil], json.values_at('attributes', 'latest_photos', 'ai_summary')
  end

  test 'summary: stats, attributes and latest photos for the retail scope' do
    create(:review_attribute, :fit)
    review_by(rating: 5, body: 'Love it', attribute_ratings: { 'fit' => 2 }, photos: [reviews_photo])
    review_by(rating: 3, attribute_ratings: { 'fit' => 3 })
    review_by(reviews_wholesale_user, rating: 1, body: 'trade only')

    get "#{@base}/review_summary"
    assert_response :success
    assert_equal [4.0, 2, 1, 1], json.values_at('average', 'ratings_count', 'reviews_count', 'photos_count')
    assert_equal [{ 'key' => 'fit', 'label' => 'Fit', 'kind' => 'bipolar', 'low_label' => 'Runs small',
                    'high_label' => 'Runs large', 'average' => 2.5, 'count' => 2 }], json['attributes']
    photo = json['latest_photos'].first
    assert_equal 'Customer photo of Rib-Knit Wrap Top', photo['alt']
    assert photo['thumb_url'].start_with?('http://www.example.com/'), photo['thumb_url']
  end

  test 'retail is the default and never includes wholesale reviews, whatever the params' do
    retail = review_by(rating: 5)
    review_by(reviews_wholesale_user, rating: 2)
    get "#{@base}/reviews"
    assert_equal [retail.id], ids
    get "#{@base}/reviews", params: { scope: 'nonsense' }
    assert_equal [retail.id], ids
  end

  test 'all and wholesale scopes need a wholesale or admin Bearer token' do
    retail = review_by(rating: 5)
    wholesale = review_by(reviews_wholesale_user, rating: 2)

    %w[all wholesale].each do |scope|
      get "#{@base}/reviews", params: { scope: scope }
      assert_response :forbidden
      get "#{@base}/reviews", params: { scope: scope }, headers: auth(create(:user))
      assert_response :forbidden
      get "#{@base}/review_summary", params: { scope: scope }
      assert_response :forbidden
    end

    get "#{@base}/reviews", params: { scope: 'all' }, headers: auth(reviews_wholesale_user)
    assert_response :success
    assert_equal [retail.id, wholesale.id].sort, ids.sort
    assert_equal 'all', json['meta']['scope']

    get "#{@base}/reviews", params: { scope: 'wholesale' }, headers: auth(media_admin)
    assert_equal [wholesale.id], ids
    assert_equal 'wholesale', json['data'].first['channel']
  end

  test "the storefront's api key never unlocks wholesale reviews, even an admin's key" do
    review_by(reviews_wholesale_user, rating: 2)
    admin = media_admin
    admin.generate_spree_api_key!
    get "#{@base}/reviews", params: { scope: 'all' }, headers: { 'X-Spree-Token' => admin.spree_api_key }
    assert_response :forbidden
    get "#{@base}/reviews", headers: { 'X-Spree-Token' => admin.spree_api_key }
    assert_response :success
  end

  test 'an invalid Bearer token is refused' do
    get "#{@base}/reviews", headers: bearer('not-a-token')
    assert_response :unauthorized
  end

  test 'only published reviews are listed' do
    published = review_by(rating: 4)
    held = review_by(rating: 5, body: 'see www.spam.example')
    rejected = review_by(rating: 1)
    Reviews::Moderation.reject!(rejected, reason: 'spam', by: media_admin)
    hidden = review_by(rating: 2)
    Reviews::Moderation.hide!(hidden, by: media_admin)

    get "#{@base}/reviews"
    assert_equal [published.id], ids
    refute_includes response.body, held.body
  end

  test 'sorting: most helpful by default, then newest, highest and lowest rating' do
    low = review_by(rating: 1, body: 'not for me')
    high = review_by(rating: 5)
    mid = review_by(rating: 3)
    low.update_columns(helpful_count: 9, published_at: 3.days.ago)
    high.update_columns(helpful_count: 2, published_at: 2.days.ago)
    mid.update_columns(helpful_count: 2, published_at: 1.day.ago)

    get "#{@base}/reviews"
    assert_equal [low.id, mid.id, high.id], ids, 'helpful first; ties go to the newest'
    get "#{@base}/reviews", params: { sort: 'recent' }
    assert_equal [mid.id, high.id, low.id], ids
    get "#{@base}/reviews", params: { sort: 'rating_desc' }
    assert_equal [high.id, mid.id, low.id], ids
    get "#{@base}/reviews", params: { sort: 'rating_asc' }
    assert_equal [low.id, mid.id, high.id], ids
  end

  test 'filters: ratings, with photos, written only' do
    five = review_by(rating: 5, body: 'Great')
    four_photo = review_by(rating: 4, photos: [reviews_photo])
    review_by(rating: 1)

    get "#{@base}/reviews", params: { rating: %w[5 4] }
    assert_equal [five.id, four_photo.id].sort, ids.sort
    get "#{@base}/reviews", params: { with_photos: '1' }
    assert_equal [four_photo.id], ids
    get "#{@base}/reviews", params: { written: '1' }
    assert_equal [five.id], ids
  end

  test 'pagination meta' do
    3.times { review_by(rating: 5) }
    get "#{@base}/reviews", params: { per_page: 2, page: 2 }
    assert_equal 1, json['data'].size
    assert_equal({ 'page' => 2, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2, 'scope' => 'retail' }, json['meta'])
    get "#{@base}/reviews", params: { per_page: 500 }
    assert_equal 50, json['meta']['per_page']
  end

  test 'a review shows what shoppers need and nothing about who wrote it' do
    user = create(:user, email: 'maya.private@example.com')
    review = review_by(user, rating: 4, title: 'Runs small', body: 'Size up', photos: [reviews_photo])
    review.update!(reply_body: 'Thanks Maya', replied_at: Time.current)

    get "#{@base}/reviews"
    data = json['data'].first
    assert_equal %w[id rating title body display_name variant_label verified_purchase incentivized channel
                    attribute_ratings photos helpful_count unhelpful_count reply published_at edited].sort, data.keys.sort
    assert_equal ['Maya R.', true, true, 'retail'], data.values_at('display_name', 'verified_purchase', 'incentivized', 'channel')
    assert_equal 'Thanks Maya', data['reply']['body']
    assert_equal %w[alt card_url full_url id thumb_url], data['photos'].first.keys.sort
    refute_includes response.body, 'maya.private@example.com'
    refute_includes response.body, %("user_id")
  end

  test 'products are found by slug or id; hidden products are 404' do
    review_by(rating: 5)
    get "/api/v1/products/#{@product.id}/reviews"
    assert_response :success
    assert_equal 1, json['data'].size

    @product.update!(available_on: nil)
    get "#{@base}/reviews"
    assert_response :not_found
    get "#{@base}/review_summary"
    assert_response :not_found
    get '/api/v1/products/no-such-product/reviews'
    assert_response :not_found
  end

  test 'storefront v2 products carry the ratings, retail and all channels' do
    review_by(rating: 4)
    review_by(reviews_wholesale_user, rating: 2)

    get "/api/v2/storefront/products/#{@product.slug}"
    assert_response :success
    attributes = json['data']['attributes']
    assert_equal ['4.0', 1, '3.0', 2], attributes.values_at('avg_rating', 'reviews_count', 'all_avg_rating', 'all_reviews_count')

    get "/api/v2/storefront/products/#{@product.slug}", headers: auth(reviews_wholesale_user)
    assert_response :success
    assert_equal ['3.0', 2], json['data']['attributes'].values_at('all_avg_rating', 'all_reviews_count')
  end
end
