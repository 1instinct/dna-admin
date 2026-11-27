require 'test_helper'

# M5 store reviews: docs/plans/2026-11-26-reviews-api-contract.md ("M5 store reviews").
class Spree::Api::V1::StoreReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!(photos_require_approval: false, store_reviews_enabled: true)
    @store = reviews_store
    @product = media_product(name: 'Wrap Top')
    @delivery = create(:review_attribute, key: 'delivery', label: 'Delivery', applies_to: 'store')
    create(:review_attribute, key: 'quality', label: 'Quality') # a product question: never on store reviews
    @user = create(:user)
    @order = reviews_order(@product, user: @user)
    @headers = auth(@user)
  end

  def json
    JSON.parse(response.body)
  end

  def post_store_review(headers: @headers, **params)
    post '/api/v1/store_reviews', params: params, headers: headers, as: :json
  end

  # A published store review from another buyer.
  def store_review_by(user = create(:user), channel: 'spree', **params)
    reviews_order(@product, user: user, channel: channel)
    reviews_submit(@store, user: user, **params).review
  end

  test 'every endpoint is 503 not_enabled while reviews or store reviews are off' do
    [{ enabled: false }, { store_reviews_enabled: false }].each do |off|
      reviews_enable!(store_reviews_enabled: true)
      reviews_enable!(**off)
      get '/api/v1/store_reviews/summary'
      assert_response :service_unavailable
      assert_equal 'not_enabled', json['code']
      get '/api/v1/store_reviews'
      assert_response :service_unavailable
      get '/api/v1/store_reviews/form', headers: @headers
      assert_response :service_unavailable
      post_store_review(rating: 5)
      assert_response :service_unavailable
      patch '/api/v1/store_reviews/1', params: { rating: 5 }, headers: @headers, as: :json
      assert_response :service_unavailable
    end
  end

  test 'a buyer writes a store review: no product, no points, no variant' do
    post_store_review(rating: 5, title: 'Quick', body: 'Arrived in two days', attribute_ratings: { delivery: 5 })
    assert_response :created
    review = json['review']
    assert_equal [5, 'Quick', 'Arrived in two days', 'published', 'Your review is live.'],
                 review.values_at('rating', 'title', 'body', 'status', 'status_message')
    assert_nil review['product']
    assert_nil review['variant_label']
    assert_equal false, review['incentivized']
    assert_equal({ 'awarded' => 0, 'pending' => 0 }, review['points'])
    assert_equal({ 'delivery' => 5 }, review['attribute_ratings'])
    assert_equal 'Maya R.', review['display_name']
    assert_equal [], review['photos']

    stored = Spree::Review.find(review['id'])
    assert_equal [@store, @order, 'web', nil], [stored.reviewable, stored.order, stored.source, stored.points_awarded_at]
    assert_equal 0, Spree::LoyaltyPointsTransaction.where(source: stored).count, 'store reviews earn no points'
    assert_equal 0, @product.reload.reviews_count, "a store review isn't a product review"
  end

  test 'one per account: a second POST is 409 with the review id, PATCH edits it' do
    post_store_review(rating: 5)
    id = json['review']['id']

    post_store_review(rating: 1)
    assert_response :conflict
    assert_equal({ 'code' => 'already_reviewed', 'review_id' => id }, json.slice('code', 'review_id'))

    patch "/api/v1/store_reviews/#{id}", params: { rating: 3, body: 'Changed my mind' }, headers: @headers, as: :json
    assert_response :ok
    assert_equal [id, 3, 'Changed my mind', true], json['review'].values_at('id', 'rating', 'body', 'edited')
    assert_equal 1, Spree::Review.for_store.count
    assert_equal @order.id, Spree::Review.find(id).order_id

    patch "/api/v1/store_reviews/#{id}", params: { rating: 1 }, headers: auth(create(:user)), as: :json
    assert_response :not_found
    product_review = reviews_submit(@product, user: @user, rating: 4).review
    patch "/api/v1/store_reviews/#{product_review.id}", params: { rating: 1 }, headers: @headers, as: :json
    assert_response :not_found, 'PATCH reaches store reviews only'
  end

  test 'errors: signed out, no shipped order, staff, photos, unknown question, invalid rating' do
    post_store_review(headers: {}, rating: 5)
    assert_response :unauthorized
    post_store_review(headers: { 'Authorization' => 'Bearer nope' }, rating: 5)
    assert_response :unauthorized

    not_shipped = create(:user)
    reviews_order(@product, user: not_shipped, shipped: false)
    post_store_review(headers: auth(not_shipped), rating: 5)
    assert_response :forbidden
    assert_equal 'not_eligible', json['code']

    post_store_review(headers: auth(media_admin), rating: 5)
    assert_response :forbidden
    assert_equal 'forbidden', json['code']

    photo = Rack::Test::UploadedFile.new(StringIO.new(ShopMediaTestHelper::PNG_BYTES), 'image/png', original_filename: 'p.png')
    post '/api/v1/store_reviews', params: { rating: 5, photos: [photo] }, headers: @headers
    assert_response :unprocessable_entity
    assert_equal 'invalid', json['code']
    assert json['fields']['photos'].any?

    post_store_review(rating: 5, attribute_ratings: { quality: 4 })
    assert_response :unprocessable_entity
    assert_equal 'invalid', json['code']

    post_store_review(rating: 9)
    assert_response :unprocessable_entity
    assert json['fields']['rating'].any?
    assert_equal 0, Spree::Review.for_store.count
  end

  test 'held store reviews say so and show no points to come' do
    post_store_review(rating: 2, body: 'call me on 555 010 0100 1234')
    assert_response :created
    assert_equal 'pending', json['review']['status']
    assert_equal({ 'awarded' => 0, 'pending' => 0 }, json['review']['points'])
  end

  test 'form: eligibility, display name, store questions, the existing review' do
    get '/api/v1/store_reviews/form'
    assert_response :unauthorized

    get '/api/v1/store_reviews/form', headers: @headers
    assert_response :success
    assert_equal true, json['eligible']
    assert_nil json['reason']
    assert_equal 'Maya R.', json['display_name']
    assert_equal [{ 'key' => 'delivery', 'label' => 'Delivery', 'kind' => 'scale', 'low_label' => nil, 'high_label' => nil }],
                 json['questions']
    assert_nil json['existing_review']
    assert_equal({ 'title_max' => 120, 'body_max' => 5000 }, json['limits'])

    post_store_review(rating: 4, display_name: 'Maya')
    get '/api/v1/store_reviews/form', headers: @headers
    existing = json['existing_review']
    assert_equal [4, 'published', nil], existing.values_at('rating', 'status', 'product')
    assert_equal({ 'awarded' => 0, 'pending' => 0 }, existing['points'])
    assert_equal 'Maya', json['display_name']

    get '/api/v1/store_reviews/form', headers: auth(create(:user))
    assert_equal [false, 'no_shipped_order'], json.values_at('eligible', 'reason')
  end

  test 'summary: retail store reviews with the store questions, no photos, no AI summary' do
    store_review_by(rating: 5, body: 'Fast', attribute_ratings: { delivery: 5 })
    store_review_by(rating: 3, attribute_ratings: { delivery: 3 })
    store_review_by(reviews_wholesale_user, rating: 1, body: 'Trade order was late')
    reviews_submit(@product, user: @user, rating: 1)

    get '/api/v1/store_reviews/summary'
    assert_response :success
    body = json
    assert_equal ['retail', 4.0, 2, 1], body.values_at('scope', 'average', 'ratings_count', 'reviews_count')
    assert_equal({ '1' => 0, '2' => 0, '3' => 1, '4' => 0, '5' => 1 }, body['histogram'])
    assert_equal([['delivery', 4.0, 2]], body['attributes'].map { |a| a.values_at('key', 'average', 'count') })
    assert_nil body['ai_summary']
    refute body.key?('latest_photos')
  end

  test 'summary with no store reviews is zeros' do
    get '/api/v1/store_reviews/summary'
    assert_response :success
    assert_equal [0.0, 0, 0, []], json.values_at('average', 'ratings_count', 'reviews_count', 'attributes')
    assert_equal (1..5).to_h { |n| [n.to_s, 0] }, json['histogram']
  end

  test 'list: published retail store reviews only, with filters and paging' do
    five = store_review_by(rating: 5, body: 'Lovely packaging')
    three = store_review_by(rating: 3)
    wholesale = store_review_by(reviews_wholesale_user, rating: 4, body: 'Trade pricing was fine')
    held = store_review_by(rating: 2, body: 'see www.example.com')
    product_review = reviews_submit(@product, user: @user, rating: 5, body: 'Product').review
    assert_equal 'wholesale', wholesale.channel
    assert_equal 'pending', held.status

    get '/api/v1/store_reviews', params: { sort: 'rating_desc' }
    assert_response :success
    ids = json['data'].map { |review| review['id'] }
    assert_equal [five.id, three.id], ids
    refute_includes ids, wholesale.id
    refute_includes ids, product_review.id
    assert_equal({ 'page' => 1, 'per_page' => 10, 'total_count' => 2, 'total_pages' => 1, 'scope' => 'retail' }, json['meta'])
    first = json['data'].first
    assert_equal ['Lovely packaging', nil, 'retail', false], first.values_at('body', 'variant_label', 'channel', 'incentivized')
    refute first.key?('status'), 'the public shape'

    get '/api/v1/store_reviews', params: { written: 1 }
    assert_equal([five.id], json['data'].map { |review| review['id'] })
    get '/api/v1/store_reviews', params: { rating: [3] }
    assert_equal([three.id], json['data'].map { |review| review['id'] })
    get '/api/v1/store_reviews', params: { per_page: 1, page: 2, sort: 'rating_asc' }
    assert_equal([five.id], json['data'].map { |review| review['id'] })
    assert_equal 2, json['meta']['total_pages']
    get '/api/v1/store_reviews', params: { scope: 'all' }, headers: auth(reviews_wholesale_user)
    refute_includes json['data'].map { |review| review['id'] }, wholesale.id, 'never listed, whoever asks'
  end

  test 'X-Review-Token: tied to the order, one per order, never completes the request' do
    review_requests_home!
    order = reviews_order(@product, email: 'guest@example.com')
    request, token = review_request_for(order)
    headers = { 'X-Review-Token' => token }

    post_store_review(headers: headers, rating: 4, body: 'Well packed')
    assert_response :created
    review = Spree::Review.find(json['review']['id'])
    assert_equal [order.id, 'email', nil, request.id], [review.order_id, review.source, review.user_id, review.review_request_id]
    assert_nil json['review']['product']
    request.reload
    assert_equal 'sent', request.status, "a store review alone doesn't complete the request"
    assert request.opened_at

    post_store_review(headers: headers, rating: 2)
    assert_response :conflict
    assert_equal ['already_reviewed', review.id], json.values_at('code', 'review_id')

    patch "/api/v1/store_reviews/#{review.id}", params: { rating: 5, body: 'Even better' }, headers: headers, as: :json
    assert_response :ok
    assert_equal [5, 'Even better'], json['review'].values_at('rating', 'body')

    own = store_review_by(rating: 3)
    patch "/api/v1/store_reviews/#{own.id}", params: { rating: 1 }, headers: headers, as: :json
    assert_response :not_found, "the link reaches only its order's review"

    get "/api/v1/review_requests/#{token}"
    assert_equal review.id, json['store_review']['existing_review']['id']
  end

  test 'X-Review-Token: the buyer account gets the review, a Bearer sent along does not' do
    request, token = review_request_for(@order)
    stranger = create(:user)
    post_store_review(headers: auth(stranger).merge('X-Review-Token' => token), rating: 5)
    assert_response :created
    assert_equal @user.id, Spree::Review.find(json['review']['id']).user_id

    post_store_review(rating: 4)
    assert_response :conflict, 'the account already has its store review'
    assert_equal 'sent', request.reload.status
  end

  test 'X-Review-Token: an invalid link is 404 invalid_token' do
    post_store_review(headers: { 'X-Review-Token' => 'nope' }, rating: 5)
    assert_response :not_found
    assert_equal 'invalid_token', json['code']

    _request, token = review_request_for(reviews_order(@product), status: 'expired')
    post_store_review(headers: { 'X-Review-Token' => token }, rating: 5)
    assert_response :not_found
    assert_equal 'invalid_token', json['code']
  end

  test 'a product request with every item reviewed completes; the store review is extra' do
    request, token = review_request_for(@order)
    headers = { 'X-Review-Token' => token }
    post_store_review(headers: headers, rating: 5)
    assert_equal 'sent', request.reload.status
    post '/api/v1/reviews', params: { product_id: @product.slug, rating: 5 }, headers: headers
    assert_response :created
    assert_equal 'completed', request.reload.status
  end

  test 'rate limit: the account limit for reviews applies' do
    post_store_review(rating: 5)
    id = json['review']['id']
    9.times { patch "/api/v1/store_reviews/#{id}", params: { rating: 4 }, headers: @headers, as: :json }
    assert_response :ok
    patch "/api/v1/store_reviews/#{id}", params: { rating: 4 }, headers: @headers, as: :json
    assert_response :too_many_requests
  end
  test 'an edit keeps the order the review was written for; publishing later pays no points' do
    post_store_review(rating: 2, body: 'see www.example.com')
    id = json['review']['id']
    assert_equal 'pending', json['review']['status']
    newer = reviews_order(@product, user: @user, completed_at: 1.hour.from_now)

    patch "/api/v1/store_reviews/#{id}", params: { rating: 4, body: 'All good now' }, headers: @headers, as: :json
    assert_response :ok
    review = Spree::Review.find(id)
    assert_equal @order.id, review.order_id
    refute_equal newer.id, review.order_id

    Reviews::Moderation.publish!(review.reload, by: media_admin)
    assert review.reload.published?
    assert_nil review.points_awarded_at
    assert_equal 0, Spree::LoyaltyPointsTransaction.where(source: review).count
    get '/api/v1/store_reviews/form', headers: @headers
    assert_equal({ 'awarded' => 0, 'pending' => 0 }, json['existing_review']['points'])
  end
end
