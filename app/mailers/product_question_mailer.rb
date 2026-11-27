# "Your question has an answer": sent to the shopper who asked a product question when staff
# publish an official answer in admin (Reviews > Questions, via Reviews::Questions.answer!). Sent
# inline with deliver_now; there is no job queue.
#
# Links to the question on the product page: #{SITE_URL}/#{slug}#question-#{id}.
class ProductQuestionMailer < ApplicationMailer
  layout 'store_mailer'
  helper StoreMailerHelper

  def answered(answer)
    @answer = answer
    @question = answer.question
    @product = @question.product
    @store = Reviews.store
    @store_name = @store&.name.to_s.strip.presence
    @question_url = "#{SITE_URL.to_s.chomp('/')}/#{@product.slug}#question-#{@question.id}"
    @subject = "Your question about #{@product.name} has an answer"
    from = @store&.mail_from_address.presence
    mail(**{ to: @question.user.email, subject: @subject, from: from }.compact)
  end
end
