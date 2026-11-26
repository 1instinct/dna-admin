require 'test_helper'

# M4.4: the email link's review page (docs/plans/2026-11-26-reviews-api-contract.md, "M4 email flow"):
# GET/opt-out by token, and X-Review-Token on POST/PATCH /api/v1/reviews.
class Spree::Api::V1::ReviewRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!(photos_require_approval: false, store_reviews_enabled: true)
    @top = media_product(name: 'Wrap Top')
    @skirt = media_product(name: 'Slip Skirt')
    create(:review_attribute, :fit)
    @order = reviews_order(@top, @skirt, email: 'guest@example.com')
    @review_request, @token = review_request_for(@order)
    @lines = @order.line_items.index_by { |li| li.variant.product_id }
  end

  def json
    JSON.parse(response.body)
  end

  def token_headers(token = @token)
    { 'X-Review-Token' => token }
  end

  def post_review(product, headers: token_headers, **params)
    post '/api/v1/reviews', params: { product_id: product.slug }.merge(params), headers: headers
  end

  test 'GET shows the order to review and records the first open' do
    get "/api/v1/review_requests/#{@token}"
    assert_response :success
    body = json
    assert_equal @order.number, body['order_number']
    assert_equal 'Maya R.', body['display_name']
    items = body['items'].index_by { |item| item['product_id'] }
    assert_equal [@top.id, @skirt.id].sort, items.keys.sort
    top = items.fetch(@top.id)
    assert_equal [@lines.fetch(@top.id).id, @top.slug, 'Wrap Top', nil], top.values_at('line_item_id', 'slug', 'name', 'existing_review')
    assert_equal ['fit'], top['questions'].map { |q| q['key'] }
    assert_equal({ 'enabled' => true, 'existing_review' => nil }, body['store_review'])
    assert_equal({ 'per_review' => 50, 'photo_bonus' => 50 }, body['points'])
    assert_equal false, body['has_account']
    assert_equal 5, body['limits']['max_photos']

    opened_at = @review_request.reload.opened_at
    assert opened_at
    travel 1.hour do
      get "/api/v1/review_requests/#{@token}"
    end
    assert_equal opened_at, @review_request.reload.opened_at, 'only the first open is recorded'
  end

  test 'GET is 404 for unknown, expired, opted-out and cancelled links; a completed one still opens' do
    get '/api/v1/review_requests/nope'
    assert_response :not_found

    @review_request.update!(status: 'completed', completed_at: Time.current)
    get "/api/v1/review_requests/#{@token}"
    assert_response :success

    %w[opted_out cancelled expired].each do |status|
      @review_request.update!(status: status)
      get "/api/v1/review_requests/#{@token}"
      assert_response :not_found, status
    end

    @review_request.update!(status: 'sent', expires_at: 1.minute.ago)
    get "/api/v1/review_requests/#{@token}"
    assert_response :not_found
  end

  test 'GET is 503 while reviews are switched off' do
    reviews_enable!(enabled: false)
    get "/api/v1/review_requests/#{@token}"
    assert_response :service_unavailable
    assert_equal 'not_enabled', json['code']
  end

  test 'opt out' do
    post "/api/v1/review_requests/#{@token}/opt_out"
    assert_response :success
    assert_equal({ 'status' => 'opted_out' }, json)
    assert_equal 'opted_out', @review_request.reload.status
    assert Spree::ReviewRequest.opted_out?('GUEST@example.com')

    post "/api/v1/review_requests/#{@token}/opt_out"
    assert_response :success, 'again is fine'

    post '/api/v1/review_requests/nope/opt_out'
    assert_response :not_found
  end

  test 'a guest reviews with the email link: source email, request completed when every item is done' do
    post_review(@top, rating: 4, line_item_id: @lines.fetch(@top.id).id, body: 'Soft')
    assert_response :created
    review = Spree::Review.find(json['review']['id'])
    assert_equal ['email', @review_request.id, @order.id, nil, 4], [review.source, review.review_request_id, review.order_id,
                                                            review.user_id, review.rating]
    assert_equal 'sent', @review_request.reload.status
    assert @review_request.opened_at

    get "/api/v1/review_requests/#{@token}"
    item = json['items'].find { |i| i['product_id'] == @top.id }
    assert_equal [review.id, 'published'], item['existing_review'].values_at('id', 'status')

    post_review(@skirt, rating: 2)
    assert_response :created
    assert_equal 'completed', @review_request.reload.status
    assert @review_request.completed_at

    post_review(@skirt, rating: 3)
    assert_response :ok, 'a completed link can still edit until it expires'
    assert_equal 3, Spree::Review.find_by(order: @order, reviewable: @skirt).rating
  end

  test "the link can't reach another order's items" do
    other_product = media_product(name: 'Other')
    other_order = reviews_order(other_product)
    post_review(other_product, rating: 5)
    assert_response :forbidden
    assert_equal 'not_eligible', json['code']

    post_review(@top, rating: 5, line_item_id: other_order.line_items.first.id)
    assert_response :forbidden

    own = reviews_submit(other_product, review_request: review_request_for(other_order).first, rating: 1).review
    patch "/api/v1/reviews/#{own.id}", params: { rating: 5 }, headers: token_headers
    assert_response :not_found
    assert_equal 1, own.reload.rating
    assert_equal 0, Spree::Review.where(order: @order).count
  end

  test 'PATCH with the link edits reviews from that order' do
    post_review(@top, rating: 2)
    id = json['review']['id']
    patch "/api/v1/reviews/#{id}", params: { rating: 4, title: 'Better after washing' }, headers: token_headers
    assert_response :ok
    assert_equal [4, 'Better after washing', true], json['review'].values_at('rating', 'title', 'edited')
    assert_equal 'email', Spree::Review.find(id).source

    delete "/api/v1/reviews/#{id}", headers: token_headers
    assert_response :unauthorized, 'deleting still needs the account'
  end

  test 'bad, expired or used-up links are refused' do
    post_review(@top, headers: token_headers('nope'), rating: 5)
    assert_response :not_found
    assert_equal 'invalid_token', json['code']

    @review_request.update!(status: 'opted_out')
    post_review(@top, rating: 5)
    assert_response :not_found
    assert_equal 0, Spree::Review.count
  end

  test 'submissions per link are rate limited' do
    ReviewRequests::RateLimit::LIMIT.times { post_review(@top, rating: 3) }
    assert_response :ok
    post_review(@top, rating: 3)
    assert_response :too_many_requests
  end

  test "an account order: the review is the buyer's, even when someone else is signed in" do
    buyer = create(:user)
    order = reviews_order(@top, user: buyer)
    _request, token = review_request_for(order)
    stranger = create(:user)
    post_review(@top, headers: token_headers(token).merge(auth(stranger)), rating: 5)
    assert_response :created
    review = Spree::Review.find(json['review']['id'])
    assert_equal [buyer.id, order.id, 'email'], [review.user_id, review.order_id, review.source]
    assert_equal 50, json['review']['points']['awarded'], "the buyer's account earns the points"

    post_review(@top, headers: token_headers(token).merge(auth(buyer)), rating: 4)
    assert_response :ok
    assert_equal [buyer.id, 4], review.reload.values_at(:user_id, :rating)
  end

  test 'Bearer alone still works as before' do
    buyer = create(:user)
    reviews_order(@top, user: buyer)
    post_review(@top, headers: auth(buyer), rating: 5)
    assert_response :created
    assert_equal 'web', Spree::Review.find(json['review']['id']).source

    post_review(@top, headers: {}, rating: 5)
    assert_response :unauthorized
  end
end
