# Preview at /rails/mailers/product_question_mailer (development). Uses the newest official answer
# to a question with an asker, else an unsaved question and answer on the newest product, so
# previewing never changes data.
class ProductQuestionMailerPreview < ActionMailer::Preview
  def answered
    ProductQuestionMailer.answered(preview_answer)
  end

  private

  def preview_answer
    answer = Spree::ProductAnswer.joins(:question).where(official: true).where.not(spree_product_questions: { user_id: nil }).
             order(created_at: :desc).first
    return answer if answer

    product = Spree::Product.order(created_at: :desc).first
    user = Spree::User.order(created_at: :desc).first
    raise 'Add a product and a customer first: the preview needs both.' unless product && user

    question = Spree::ProductQuestion.new(id: 0, product: product, user: user, display_name: 'Maya R.', status: 'published',
                                          body: 'Is the fabric see-through in the white?', created_at: Time.current)
    Spree::ProductAnswer.new(question: question, body: "It's fully opaque, even in the white.", official: true,
                             status: 'published', display_name: Reviews::Questions.store_name, published_at: Time.current)
  end
end
