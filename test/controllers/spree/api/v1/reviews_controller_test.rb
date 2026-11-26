require 'test_helper'

# Writing reviews: docs/plans/2026-11-26-reviews-api-contract.md ("M2 write path").
class Spree::Api::V1::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!(photos_require_approval: false)
    @product = media_product(name: 'Rib-Knit Wrap Top')
    @user = create(:user)
    @order = reviews_order(@product, user: @user)
    @headers = auth(@user)
  end

  def json
    JSON.parse(response.body)
  end

  def upload(name = 'photo.png')
    Rack::Test::UploadedFile.new(StringIO.new(ShopMediaTestHelper::PNG_BYTES), 'image/png', original_filename: name)
  end

  def post_review(headers: @headers, **params)
    post '/api/v1/reviews', params: { product_id: @product.slug }.merge(params), headers: headers
  end

  test 'a buyer posts a star-only review and gets their own review back' do
    post_review(rating: 4)
    assert_response :created
    review = json['review']
    assert_equal [4, 'published', 'Your review is live.'], review.values_at('rating', 'status', 'status_message')
    assert_equal({ 'id' => @product.id, 'slug' => @product.slug, 'name' => 'Rib-Knit Wrap Top', 'image_url' => nil },
                 review['product'])
    assert_equal({ 'awarded' => 50, 'pending' => 0 }, review['points'])
    assert_equal 1, @product.reload.reviews_count
  end

  test 'multipart with photos, questions and text' do
    create(:review_attribute, :fit)
    post_review(rating: 5, title: 'Soft', body: 'Love the rib', display_name: 'Maya',
                attribute_ratings: { fit: '2' }, photos: [upload, upload('b.png')])
    assert_response :created
    review = json['review']
    assert_equal 2, review['photos'].size
    assert_equal({ 'fit' => 2 }, review['attribute_ratings'])
    assert_equal 'Maya', review['display_name']
    assert_equal 100, review['points']['awarded'], 'review plus photo bonus'
    blob = Spree::Review.last.photos.first.blob
    assert blob.service.exist?(blob.key)
  end

  test 'held reviews say so without naming a reason, and show the points still to come' do
    post_review(rating: 2, body: 'see www.example.com')
    assert_response :created
    assert_equal ['pending', "Thanks! We're checking it before it goes live."], json['review'].values_at('status', 'status_message')
    assert_equal({ 'awarded' => 0, 'pending' => 50 }, json['review']['points'])
    refute_includes response.body, 'auto_flag'
  end

  test 'posting again edits the same review' do
    post_review(rating: 5, body: 'First')
    id = json['review']['id']
    post_review(rating: 3, body: 'Changed my mind')
    assert_response :ok
    assert_equal [id, 3, true], json['review'].values_at('id', 'rating', 'edited')
    assert_equal 1, Spree::Review.count
  end

  test 'errors: signed out, not bought, staff, invalid, switched off' do
    post_review(headers: {}, rating: 5)
    assert_response :unauthorized

    post_review(headers: auth(create(:user)), rating: 5)
    assert_response :forbidden
    assert_equal 'not_eligible', json['code']

    post_review(headers: auth(media_admin), rating: 5)
    assert_response :forbidden
    assert_equal 'forbidden', json['code']

    post_review(rating: 9)
    assert_response :unprocessable_entity
    assert json['fields']['rating'].any?

    post_review(rating: 4, attribute_ratings: { smell: 3 })
    assert_response :unprocessable_entity
    assert_equal 'invalid', json['code']

    post_review(rating: 4, photos: Array.new(6) { |i| upload("p#{i}.png") })
    assert_response :unprocessable_entity
    assert json['fields']['photos'].any?

    reviews_enable!(enabled: false)
    post_review(rating: 4)
    assert_response :service_unavailable
    assert_equal 'not_enabled', json['code']
  end

  test 'rate limit: ten submissions an hour' do
    10.times { post_review(rating: 4) }
    assert_response :success
    post_review(rating: 4)
    assert_response :too_many_requests
  end

  test 'PATCH edits text, adds and removes photos, and only for the owner' do
    post_review(rating: 5, photos: [upload('a.png'), upload('b.png')])
    review = json['review']
    keep, remove = review['photos'].map { |photo| photo['id'] }

    patch "/api/v1/reviews/#{review['id']}", params: { rating: 4, body: 'Updated', remove_photo_ids: [remove],
                                                       photos: [upload('c.png')] }, headers: @headers
    assert_response :ok
    assert_equal [4, 'Updated'], json['review'].values_at('rating', 'body')
    assert_equal 2, json['review']['photos'].size
    assert_includes json['review']['photos'].map { |photo| photo['id'] }, keep
    refute_includes json['review']['photos'].map { |photo| photo['id'] }, remove

    patch "/api/v1/reviews/#{review['id']}", params: { photos: Array.new(4) { |i| upload("x#{i}.png") } }, headers: @headers
    assert_response :unprocessable_entity

    patch "/api/v1/reviews/#{review['id']}", params: { rating: 1 }, headers: auth(create(:user))
    assert_response :not_found
  end

  test 'DELETE removes the review and its effect on the stats; points stay' do
    post_review(rating: 5, photos: [upload])
    id = json['review']['id']
    blob = Spree::Review.find(id).photos.first.blob
    delete "/api/v1/reviews/#{id}", headers: auth(create(:user))
    assert_response :not_found

    delete "/api/v1/reviews/#{id}", headers: @headers
    assert_response :no_content
    refute Spree::Review.exists?(id)
    refute ActiveStorage::Blob.exists?(blob.id)
    assert_equal 0, @product.reload.reviews_count
    assert_equal 100, @user.reload.loyalty_points_balance
  end

  test 'votes: signed in or by visitor id, one each, not on your own review' do
    post_review(rating: 5, body: 'Helpful')
    id = json['review']['id']

    post "/api/v1/reviews/#{id}/votes", params: { helpful: true }, headers: @headers
    assert_response :unprocessable_entity, 'own review'

    voter = auth(create(:user))
    post "/api/v1/reviews/#{id}/votes", params: { helpful: true }, headers: voter
    post "/api/v1/reviews/#{id}/votes", params: { helpful: true }, headers: voter
    post "/api/v1/reviews/#{id}/votes", params: { helpful: 'true' }, headers: { 'X-Visitor-Id' => 'v-1' }
    assert_response :success
    assert_equal({ 'helpful_count' => 2, 'unhelpful_count' => 0, 'your_vote' => true }, json)

    post "/api/v1/reviews/#{id}/votes", params: { helpful: false }, headers: voter
    assert_equal [1, 1], json.values_at('helpful_count', 'unhelpful_count')

    post "/api/v1/reviews/#{id}/votes", params: { helpful: true }
    assert_response :unprocessable_entity, 'anonymous without a visitor id'

    post '/api/v1/reviews/999999/votes', params: { helpful: true }, headers: voter
    assert_response :not_found
  end

  test 'reports: three open reports send a review back to moderation' do
    post_review(rating: 1, body: 'Not for me')
    id = json['review']['id']

    post '/api/v1/reports', params: { target: { type: 'review', id: id }, reason: 'spam' }, headers: @headers
    assert_response :unprocessable_entity, 'own review'

    3.times do |i|
      post '/api/v1/reports', params: { target: { type: 'review', id: id }, reason: 'other', details: "r#{i}" },
                              headers: auth(create(:user))
      assert_response :created
    end
    review = Spree::Review.find(id)
    assert_equal ['pending', 'reported', 3], [review.status, review.moderation_reason, review.reports_count]
    assert_equal 'Not for me', Spree::ContentReport.last.snapshot['body']
    assert_equal 0, @product.reload.reviews_count

    post '/api/v1/reports', params: { target: { type: 'review', id: id }, reason: 'spam' }, headers: auth(create(:user))
    assert_response :not_found, 'no longer published'
  end
end
