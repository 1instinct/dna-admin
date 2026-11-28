module Spree
  module Api
    module V1
      module Storefront
        # The customer's side of the chat. Staff notes are never sent here.
        #
        #   GET  chat                  { visitor_token, conversation | null, greeting, online }
        #   GET  chat/messages?after=  { visitor_token, conversation_id, messages: [...] } oldest first
        #   POST chat/messages         { body, name?, email? } -> 201 { visitor_token, conversation, message }
        #   POST chat/read             { visitor_token, conversation | null }
        #   GET  chat/resume?token=    { visitor_token, conversation, messages, greeting, online }
        #
        # Plain JSON, no { data } envelope: messages always under messages (an array), a new message
        # under message. visitor_token is always the one to keep (the widget switches when it
        # differs, e.g. after resume). GET chat makes nothing and is cheap to poll; it shows a
        # conversation staff started from the Visitors screen.
        #
        # conversation: { id, status, unread, last_message_at, created_at }
        # message: { id, direction: inbound|outbound, body, author: { kind: customer|staff, name },
        #            attachments: [{ url, filename, content_type }], created_at, read_at }
        #
        # online is true when a paired admin device was used in the last 10 minutes or it is
        # business hours (Chat.config). A body is 1 to 4000 characters; a visitor token sends at
        # most 20 messages a minute, and an IP starts at most 5 conversations an hour.
        class ChatController < Spree::Api::V1::Storefront::BaseController
          MESSAGES_LIMIT = 100

          before_action :limit_resume, only: :resume

          def show
            contact = current_contact
            render json: chat_state(contact, contact && Chat::Conversations.current_for(contact))
          end

          def messages
            contact = current_contact
            conversation = contact && Chat::Conversations.current_for(contact)
            list = conversation ? visible_messages(conversation, after: params[:after]) : []
            Chat::Conversations.mark_delivered(list)
            render json: {
              visitor_token: contact&.visitor_token, conversation_id: conversation&.id&.to_s,
              messages: list.map { |m| Chat::Presenter.customer_message(m) }
            }
          end

          def create_message
            body = Chat::Conversations.clean_body(string_param(:body))
            fields = contact_fields
            return if performed?
            return too_many_requests(:message) unless Chat::RateLimit.allow?(:message, message_limit_key)

            contact = current_contact(create: true)
            conversation = Chat::Conversations.current_for(contact)
            if conversation.nil? && !Chat::RateLimit.allow?(:new_conversation, request.remote_ip)
              return too_many_requests(:new_conversation)
            end

            contact.update!(fields) if fields.any?
            session = contact.visitor_sessions.live.recent_first.first
            conversation ||= Chat::Conversations.find_or_create(contact, channel: 'web', visitor_session: session).first
            message = Chat::Conversations.post_inbound(conversation, body: body, visitor_session: session)
            render json: {
              visitor_token: contact.visitor_token,
              conversation: Chat::Presenter.customer_conversation(conversation.reload),
              message: Chat::Presenter.customer_message(message)
            }, status: :created
          end

          def read
            contact = current_contact
            conversation = contact && Chat::Conversations.current_for(contact)
            Chat::Conversations.mark_read_by_customer(conversation) if conversation
            render json: { visitor_token: contact&.visitor_token,
                           conversation: Chat::Presenter.customer_conversation(conversation&.reload) }
          end

          # The reply email's link: hands the widget the conversation's contact (its visitor token),
          # wherever the link is opened.
          def resume
            conversation = Chat.conversation_for_resume_token(params[:token])
            return render_error('This link is invalid or has expired.', :not_found) unless conversation

            contact = conversation.contact
            contact.update!(visitor_token: Contact.generate_visitor_token) if contact.visitor_token.blank?
            touch_last_seen(contact)
            state = chat_state(contact, conversation)
            state[:messages] = visible_messages(conversation).map { |m| Chat::Presenter.customer_message(m) }
            render json: state
          end

          private

          def chat_state(contact, conversation)
            {
              visitor_token: contact&.visitor_token,
              conversation: Chat::Presenter.customer_conversation(conversation),
              greeting: Chat.config.greeting,
              online: Chat.staff_online?
            }
          end

          # Messages after the given id, oldest first; without one, the latest MESSAGES_LIMIT.
          def visible_messages(conversation, after: nil)
            scope = conversation.messages.visible_to_customer.with_attached_attachments.includes(:sender)
            if after.present?
              scope.where('messages.id > ?', after.to_i).reorder(id: :asc).limit(MESSAGES_LIMIT).to_a
            else
              scope.reorder(id: :desc).limit(MESSAGES_LIMIT).to_a.reverse
            end
          end

          # name and email from the first message's form; an email given opts in to email replies.
          def contact_fields
            fields = {}
            name = string_param(:name)&.strip
            email = string_param(:email)&.strip
            if name.present?
              return render_error('name is too long', :unprocessable_entity, fields: { name: ['is too long'] }) if name.length > Contact::NAME_MAX

              fields[:name] = name
            end
            if email.present?
              unless email.length <= Contact::EMAIL_MAX && email.match?(URI::MailTo::EMAIL_REGEXP)
                return render_error('email is not a valid email', :unprocessable_entity, fields: { email: ['is not a valid email'] })
              end

              fields[:email] = email
              fields[:email_opt_in] = true
            end
            fields
          end

          def message_limit_key
            visitor_token_header || "ip:#{request.remote_ip}"
          end

          def limit_resume
            too_many_requests(:resume) unless Chat::RateLimit.allow?(:resume, request.remote_ip)
          end
        end
      end
    end
  end
end
