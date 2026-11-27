require 'test_helper'
require Rails.root.join('test/mailers/previews/product_question_mailer_preview').to_s

# M6: the "your question has an answer" email.
class ProductQuestionMailerTest < ActionMailer::TestCase
  setup do
    reviews_enable!(questions_enabled: true)
    @store = reviews_store
    @product = media_product(name: 'Wrap Top')
    @question = Spree::ProductQuestion.create!(product: @product, user: create(:user, email: 'jo@example.com'),
                                               body: 'Is the fabric see-through in the white?', display_name: 'Jo K.',
                                               status: 'published')
    @answer = @question.answers.create!(body: "It's fully opaque.\n\nEven in the white.", official: true, status: 'published',
                                        display_name: @store.name, published_at: Time.current)
  end

  test 'the answer, the question and a link to it on the product page, in the store frame' do
    mail = ProductQuestionMailer.answered(@answer)
    assert_equal ['jo@example.com'], mail.to
    assert_equal [@store.mail_from_address], mail.from
    assert_equal 'Your question about Wrap Top has an answer', mail.subject

    url = "#{SITE_URL.to_s.chomp('/')}/#{@product.slug}#question-#{@question.id}"
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_includes html, %(href="#{url}")
    assert_includes text, url
    assert_includes html, 'Is the fabric see-through in the white?'
    assert_includes html, "<div>It's fully opaque.</div>"
    assert_includes text, "It's fully opaque."
    assert_includes html, 'em-button', 'uses the themed frame'
    assert_includes html, EmailTheme.current[:button_bg].to_s
    assert_includes text, "© #{Time.current.year}", 'store_mailer text footer'
  end

  test 'the preview renders' do
    mail = ProductQuestionMailerPreview.new.answered
    assert_includes mail.subject, 'has an answer'
  end
end
