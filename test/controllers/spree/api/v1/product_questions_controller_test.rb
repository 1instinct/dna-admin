require 'test_helper'

# M6 product questions: docs/plans/2026-11-26-reviews-api-contract.md ("M6 questions").
class Spree::Api::V1::ProductQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reviews_enable!(questions_enabled: true)
    @store = reviews_store
    @product = media_product(name: 'Wrap Top')
    @user = create(:user)
    reviews_order(@product, user: @user)
    @headers = auth(@user)
    @admin = media_admin
  end

  def json
    JSON.parse(response.body)
  end

  def path(product = @product)
    "/api/v1/products/#{product.slug}/questions"
  end

  def ask(body = 'Is the fabric see-through in the white?', product: @product, status: 'pending', **attrs)
    Spree::ProductQuestion.create!({ product: product, user: create(:user), body: body, display_name: 'Jo K.',
                                     status: status }.merge(attrs))
  end

  def answered(body = 'Is the fabric see-through in the white?', at: Time.current, **attrs)
    question = ask(body, **attrs)
    travel_to(at) { Reviews::Questions.answer!(question, body: "Answer to #{question.id}", by: @admin) }
    question.reload
  end

  test 'only answered questions are public, and only they count' do
    shown = answered
    pending = ask('Does it run small at all?')
    rejected = ask('What is your best price?', status: 'rejected')
    published_without_answer = ask('Is it machine washable?', status: 'published', published_at: Time.current)
    with_pending_answer = ask('Does it come in black?', status: 'published', published_at: Time.current)
    with_pending_answer.answers.create!(body: 'I think so', display_name: 'Sam', status: 'pending')
    other_product = answered(product: media_product)

    get path
    assert_response :success
    ids = json['data'].map { |question| question['id'] }
    assert_equal [shown.id], ids
    [pending, rejected, published_without_answer, with_pending_answer, other_product].each { |q| refute_includes ids, q.id }
    assert_equal({ 'page' => 1, 'per_page' => 5, 'total_count' => 1, 'total_pages' => 1 }, json['meta'])
    refute_includes response.body, 'I think so'
  end

  test 'the public shape: answers official first then oldest, the store name on official answers' do
    question = answered('Is the fabric see-through in the white?', at: Time.utc(2026, 11, 11, 12))
    question.update_columns(created_at: Time.utc(2026, 11, 10, 9))
    customer = question.answers.create!(body: 'Mine is opaque', display_name: 'Sam P.', status: 'published',
                                        verified_buyer: true, published_at: Time.utc(2026, 11, 9))
    question.answers.create!(body: 'Hidden', display_name: 'Lee', status: 'rejected')

    get path
    data = json['data'].first
    assert_equal({ 'id' => question.id, 'body' => 'Is the fabric see-through in the white?', 'display_name' => 'Jo K.',
                   'asked_at' => '2026-11-10T09:00:00Z' }, data.except('answers'))
    official, other = data['answers']
    assert_equal({ 'id' => question.answers.find_by(official: true).id, 'body' => "Answer to #{question.id}",
                   'display_name' => @store.name, 'official' => true, 'verified_buyer' => false,
                   'answered_at' => '2026-11-11T12:00:00Z' }, official)
    assert_equal [customer.id, 'Sam P.', false, true], other.values_at('id', 'display_name', 'official', 'verified_buyer')
    assert_equal 2, data['answers'].size
  end

  test 'newest answer first, with paging (per_page 1-20, default 5)' do
    old = answered('Is it lined at all?', at: 3.days.ago)
    newest = answered('Is the zip on the side?', at: 1.hour.ago)
    middle = answered('How long is the hem?', at: 1.day.ago)
    get path
    assert_equal([newest.id, middle.id, old.id], json['data'].map { |question| question['id'] })

    get path, params: { per_page: 2, page: 2 }
    assert_equal([old.id], json['data'].map { |question| question['id'] })
    assert_equal({ 'page' => 2, 'per_page' => 2, 'total_count' => 3, 'total_pages' => 2 }, json['meta'])
    get path, params: { per_page: 100 }
    assert_equal 20, json['meta']['per_page']
  end

  test 'product by slug or id; hidden or unknown products are 404' do
    answered
    get "/api/v1/products/#{@product.id}/questions"
    assert_response :success
    assert_equal 1, json['data'].size

    hidden = media_product(available_on: 1.day.from_now)
    get path(hidden)
    assert_response :not_found
    get '/api/v1/products/no-such-product/questions'
    assert_response :not_found
    post path(hidden), params: { body: 'Is it coming back soon?' }, headers: @headers, as: :json
    assert_response :not_found
  end

  test '503 not_enabled while reviews or questions are off' do
    [{ enabled: false }, { questions_enabled: false }].each do |off|
      reviews_enable!(questions_enabled: true)
      reviews_enable!(**off)
      get path
      assert_response :service_unavailable
      assert_equal 'not_enabled', json['code']
      post path, params: { body: 'Is it see-through at all?' }, headers: @headers, as: :json
      assert_response :service_unavailable
      assert_equal 'not_enabled', json['code']
    end
  end

  test 'asking: pending until answered, default display name, never public before then' do
    post path, params: { body: '  Is the fabric see-through in the white?  ' }, headers: @headers, as: :json
    assert_response :created
    assert_equal({ 'status' => 'pending', 'message' => "Thanks! We'll email you when it's answered." }, json.except('id'))
    question = Spree::ProductQuestion.find(json['id'])
    assert_equal ['Is the fabric see-through in the white?', 'Maya R.', @user.id, @product.id, 'pending'],
                 question.attributes.values_at('body', 'display_name', 'user_id', 'product_id', 'status')

    post path, params: { body: 'Does the wrap tie stay put?', display_name: 'Maya' }, headers: @headers, as: :json
    assert_equal 'Maya', Spree::ProductQuestion.find(json['id']).display_name

    get path
    assert_equal [], json['data']
    assert_equal 0, json['meta']['total_count']
  end

  test 'asking: 401 signed out, 422 with fields, 429 after five a day' do
    post path, params: { body: 'Is the fabric see-through?' }, as: :json
    assert_response :unauthorized
    post path, params: { body: 'Is the fabric see-through?' }, headers: { 'Authorization' => 'Bearer nope' }, as: :json
    assert_response :unauthorized

    post path, params: { body: 'Too short' }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['body'].any?
    post path, params: { body: 'x' * 501 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['body'].any?
    post path, params: {}, headers: @headers, as: :json
    assert_response :unprocessable_entity
    post path, params: { body: 'Is it see-through at all?', display_name: 'x' * 61 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['display_name'].any?
    assert_equal 0, Spree::ProductQuestion.count

    5.times { |i| post path, params: { body: "Question number #{i} here?" }, headers: @headers, as: :json }
    assert_response :created
    post path, params: { body: 'One question too many?' }, headers: @headers, as: :json
    assert_response :too_many_requests
    assert_equal 5, Spree::ProductQuestion.count

    travel 25.hours do
      post path, params: { body: 'A new day, a new question?' }, headers: auth(@user), as: :json
      assert_response :created
    end
  end
end
