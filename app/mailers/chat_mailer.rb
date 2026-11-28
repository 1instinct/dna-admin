# "You have a reply": a staff reply to a customer who has left the storefront, with a link that
# reopens the chat there (Chat::Channels::Email decides when).
class ChatMailer < ApplicationMailer
  layout false

  def reply(message)
    @message = message
    @conversation = message.thread_table
    @contact = @conversation.contact
    @store_name = Spree::Store.default&.name.presence || 'our store'
    @staff_name = Chat.staff_display_name
    @link = resume_link(@conversation)
    from = Spree::Store.default&.mail_from_address.presence
    mail(**{ to: @contact.email, subject: "You have a reply from #{@store_name}", from: from }.compact)
  end

  private

  # The storefront's home page with ?chat=<token>; the widget opens and resumes from it.
  def resume_link(conversation)
    "#{Chat.config.storefront_url}/?chat=#{CGI.escape(Chat.resume_token(conversation))}"
  end
end
