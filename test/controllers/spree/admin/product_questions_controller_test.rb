require 'test_helper'

# Reviews > Questions (M6): the question queue, the official answer form and the asker's email.
class Spree::Admin::ProductQuestionsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ActionMailer::TestHelper

  setup do
    reviews_enable!(questions_enabled: true)
    @store = reviews_store
    @admin = media_admin
    @product = media_product(name: 'Wrap Top')
    @asker = create(:user, email: 'jo@example.com')
    @question = Spree::ProductQuestion.create!(product: @product, user: @asker, body: 'Is the fabric see-through in the white?',
                                               display_name: 'Jo K.', status: 'pending')
    @old = Spree::ProductQuestion.create!(product: @product, user: create(:user), body: 'How long is the hem exactly?',
                                          display_name: 'Sam P.', status: 'rejected')
  end

  teardown { Warden.test_reset! }

  def public_ids
    get "/api/v1/products/#{@product.slug}/questions"
    JSON.parse(response.body)['data'].map { |question| question['id'] }
  end

  test 'admin only' do
    get '/admin/questions'
    refute_includes response.body, "question_#{@question.id}"
    login_as(create(:user), scope: :spree_user)
    get '/admin/questions'
    refute_includes response.body, "question_#{@question.id}"
    post "/admin/questions/#{@question.id}/answer", params: { answer_body: 'Sneaky' }
    assert_equal 0, Spree::ProductAnswer.count
  end

  test 'the queue shows waiting questions by default; filters' do
    login_as(@admin, scope: :spree_user)
    get '/admin/questions'
    assert_response :success
    assert_includes response.body, "question_#{@question.id}"
    refute_includes response.body, "question_#{@old.id}"
    assert_includes response.body, 'sidebar_product_questions'
    assert_includes response.body, 'sidebar_store_reviews'

    get '/admin/questions', params: { status: 'all' }
    assert_includes response.body, "question_#{@old.id}"
    get '/admin/questions', params: { status: 'all', q: 'hem' }
    assert_includes response.body, "question_#{@old.id}"
    refute_includes response.body, "question_#{@question.id}"
  end

  test 'answering publishes an official answer and the question, and emails the asker' do
    login_as(@admin, scope: :spree_user)
    get "/admin/questions/#{@question.id}"
    assert_response :success
    assert_includes response.body, 'answer_form'
    assert_includes response.body, 'Wrap Top'
    assert_equal [], public_ids

    assert_emails 1 do
      post "/admin/questions/#{@question.id}/answer", params: { answer_body: "It's fully opaque, even in the white." }
    end
    assert_redirected_to "/admin/questions/#{@question.id}"
    answer = @question.answers.last
    assert_equal [true, 'published', @admin.id, @store.name, false],
                 [answer.official, answer.status, answer.user_id, answer.display_name, answer.verified_buyer]
    assert answer.published_at
    @question.reload
    assert_equal ['published', 1], [@question.status, @question.answers_count]
    assert @question.published_at

    mail = ActionMailer::Base.deliveries.last
    assert_equal ['jo@example.com'], mail.to
    assert_includes mail.html_part.body.to_s, "#{SITE_URL.to_s.chomp('/')}/#{@product.slug}#question-#{@question.id}"
    assert_includes mail.text_part.body.to_s, "It's fully opaque, even in the white."

    assert_equal [@question.id], public_ids
  end

  test 'a blank answer is refused' do
    login_as(@admin, scope: :spree_user)
    assert_no_emails do
      post "/admin/questions/#{@question.id}/answer", params: { answer_body: '  ' }
    end
    assert_equal 0, @question.answers.count
    assert_equal 'pending', @question.reload.status
  end

  test 'no email when the asker has no account any more' do
    AccountDeletion.call(@asker)
    login_as(@admin, scope: :spree_user)
    assert_no_emails do
      post "/admin/questions/#{@question.id}/answer", params: { answer_body: 'Yes, fully opaque.' }
    end
    assert_equal 'published', @question.reload.status
    assert_equal 'Former customer', @question.display_name
  end

  test 'rejecting sends no email and keeps the question off the page' do
    login_as(@admin, scope: :spree_user)
    assert_no_emails { post "/admin/questions/#{@question.id}/reject" }
    assert_equal 'rejected', @question.reload.status
    assert_equal [], public_ids
  end

  test 'removing the last answer sends the question back to the queue' do
    Reviews::Questions.answer!(@question, body: 'First answer', by: @admin)
    second = Reviews::Questions.answer!(@question, body: 'Second answer', by: @admin)
    first = @question.answers.find_by(body: 'First answer')
    login_as(@admin, scope: :spree_user)

    delete "/admin/questions/#{@question.id}/answers/#{first.id}"
    assert_redirected_to "/admin/questions/#{@question.id}"
    assert_equal ['published', 1], @question.reload.values_at(:status, :answers_count)
    assert_equal [@question.id], public_ids

    delete "/admin/questions/#{@question.id}/answers/#{second.id}"
    assert_equal ['pending', 0], @question.reload.values_at(:status, :answers_count)
    assert_nil @question.published_at
    assert_equal [], public_ids
  end
end
