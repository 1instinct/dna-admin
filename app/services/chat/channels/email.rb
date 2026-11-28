module Chat
  module Channels
    # "You have a reply": the staff reply and a link back to the storefront chat
    # (?chat=<signed token>, see Chat.resume_token), through ChatMailer and the app's mailer
    # settings. Sent only when the customer has an email, hasn't been seen for
    # Chat.config.offline_after, a storefront URL is configured, and no reply email went out for
    # this conversation in the last Chat.config.email_throttle since they were last seen.
    class Email
      def deliver(message)
        return unless sendable?(message)

        ChatMailer.reply(message).deliver_later
        message.update_columns(channel: 'email', delivery_status: 'sent')
        true
      end

      def sendable?(message, now: Time.current)
        conversation = message.thread_table
        contact = conversation&.contact
        return false unless message.direction == 'outbound' && contact
        return false if contact.email.blank? || !contact.email.match?(URI::MailTo::EMAIL_REGEXP)
        return false if contact.online?(Chat.config.offline_after)
        return false unless Chat.config.storefront_url

        !recently_emailed?(conversation, contact, message, now)
      end

      private

      def recently_emailed?(conversation, contact, message, now)
        since = [now - Chat.config.email_throttle, contact.last_seen_at].compact.max
        conversation.messages.outbound.where(channel: 'email').where.not(id: message.id)
                    .where('messages.created_at > ?', since).exists?
      end
    end
  end
end
