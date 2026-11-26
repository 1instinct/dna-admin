require 'test_helper'

class Spree::Api::V1::AccountReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!
    @top = media_product(name: 'Wrap Top')
    @skirt = media_product(name: 'Slip Skirt')
    @user = create(:user)
    @headers = auth(@user)
  end

  def json
    JSON.parse(response.body)
  end

  test 'everything here needs a signed-in customer' do
    %w[/api/v1/account/reviewables /api/v1/account/reviews].each do |path|
      get path
      assert_response :unauthorized
    end
    get "/api/v1/products/#{@top.slug}/review_form"
    assert_response :unauthorized
  end

  test 'reviewables: shipped products, newest first, with the review and questions' do
    create(:review_attribute, :fit)
    reviews_order(@top, user: @user, completed_at: 2.days.ago)
    order = reviews_order(@skirt, user: @user, completed_at: 1.day.ago)
    reviews_order(media_product(name: 'Not shipped'), user: @user, shipped: false)
    reviews_submit(@top, user: @user, rating: 4)

    get '/api/v1/account/reviewables', headers: @headers
    assert_response :success
    assert_equal [@skirt.slug, @top.slug], json['data'].map { |item| item['slug'] }
    skirt = json['data'].first
    assert_equal [order.number, order.line_items.first.id, nil], skirt.values_at('order_number', 'line_item_id', 'existing_review')
    assert_equal [{ 'key' => 'fit', 'label' => 'Fit', 'kind' => 'bipolar', 'low_label' => 'Runs small',
                    'high_label' => 'Runs large' }], skirt['questions']
    assert_equal 4, json['data'].last['existing_review']['rating']
    assert_equal({ 'per_review' => 50, 'photo_bonus' => 50 }, json['points'])
  end

  test 'my reviews: any status, newest first, never anyone else\'s' do
    reviews_order(@top, @skirt, user: @user)
    reviews_submit(@top, user: @user, rating: 5)
    reviews_submit(@skirt, user: @user, rating: 2, body: 'www.link.example')
    other = create(:user)
    reviews_order(@top, user: other)
    reviews_submit(@top, user: other, rating: 1)

    get '/api/v1/account/reviews', headers: @headers
    assert_equal [['Slip Skirt', 'pending'], ['Wrap Top', 'published']],
                 json['data'].map { |review| [review['product']['name'], review['status']] }
    assert_equal 2, json['meta']['total_count']
  end

  test 'review form: eligible, with the purchase, questions, name, points and limits' do
    order = reviews_order(@top, user: @user)
    get "/api/v1/products/#{@top.slug}/review_form", headers: @headers
    assert_response :success
    assert_equal [true, nil, order.line_items.first.id, nil, 'Maya R.'],
                 json.values_at('eligible', 'reason', 'line_item_id', 'existing_review', 'display_name')
    assert_equal 5, json['limits']['max_photos']

    reviews_submit(@top, user: @user, rating: 3, display_name: 'M. R.')
    get "/api/v1/products/#{@top.slug}/review_form", headers: @headers
    assert_equal [3, 'M. R.'], [json['existing_review']['rating'], json['display_name']]
  end

  test 'review form: why someone cannot review' do
    get "/api/v1/products/#{@top.slug}/review_form", headers: @headers
    assert_equal [false, 'not_purchased'], json.values_at('eligible', 'reason')

    reviews_order(@top, user: @user, shipped: false)
    get "/api/v1/products/#{@top.slug}/review_form", headers: @headers
    assert_equal [false, 'not_shipped'], json.values_at('eligible', 'reason')

    get "/api/v1/products/#{@top.slug}/review_form", headers: auth(media_admin)
    assert_equal [false, 'staff'], json.values_at('eligible', 'reason')

    get '/api/v1/products/nope/review_form', headers: @headers
    assert_response :not_found
  end
end
