module Chat
  # Plain hashes for conversations and messages: the admin app's shapes (spec §2, returned by
  # Chat::InboxAdapter) and the storefront widget's (Spree::Api::V1::Storefront::ChatController).
  # Ids are strings and times ISO 8601 in UTC.
  module Presenter
    module_function

    # --- Admin (inbox) ---------------------------------------------------------------------------

    def conversation(conversation, last_message: :load)
      contact = conversation.contact
      last = last_message == :load ? conversation.last_visible_message : last_message
      {
        id: conversation.id.to_s,
        status: conversation.status,
        channel: conversation.channel.presence || 'web',
        subject: conversation.subject.presence,
        customer: customer(contact),
        assignee: staff(conversation.assignee),
        unread: conversation.staff_unread_count.to_i,
        last_message: last && {
          body: last.body.to_s.truncate(280),
          direction: last.direction || 'inbound',
          at: time(last.created_at)
        },
        updated_at: time(conversation.updated_at),
        snoozed_until: time(conversation.snoozed_until)
      }
    end

    def customer(contact)
      return { name: nil, email: nil, avatar_url: nil, contact_id: nil, user_id: nil } unless contact

      {
        name: contact.display_name,
        email: contact.email.presence,
        avatar_url: nil,
        contact_id: contact.id.to_s,
        user_id: contact.user_id&.to_s
      }
    end

    def staff(user)
      user && { id: user.id.to_s, email: user.email }
    end

    def message(message)
      {
        id: message.id.to_s,
        direction: message.direction || legacy_direction(message),
        body: message.body.to_s,
        channel: message.channel.presence || message.thread_table&.channel.presence || 'web',
        author: author(message),
        attachments: attachments(message),
        created_at: time(message.created_at),
        read_at: time(message.read_at),
        delivery: message.delivery_status
      }
    end

    def author(message)
      case message.direction || legacy_direction(message)
      when 'inbound'
        { kind: 'customer', name: message.sender.respond_to?(:display_name) ? message.sender.display_name : nil }
      else
        staff = message.author || (message.sender if message.sender.is_a?(Spree::User))
        staff ? { kind: 'staff', name: staff.email } : { kind: 'system', name: nil }
      end
    end

    def attachments(message)
      return [] unless message.attachments.attached?

      message.attachments.map do |attachment|
        { url: Chat::Urls.blob(attachment), filename: attachment.filename.to_s, content_type: attachment.content_type }
      end
    end

    # Older messages have no direction: from a contact is inbound, anything else outbound.
    def legacy_direction(message)
      message.sender_type == 'Contact' ? 'inbound' : 'outbound'
    end

    def customer_context(conversation)
      contact = conversation.contact
      session = conversation.visitor_session || contact&.visitor_sessions&.recent_first&.first
      user = contact&.user
      {
        contact: contact && { id: contact.id.to_s, name: contact.display_name, email: contact.email.presence,
                              phone: contact.phone.presence },
        user: user && { id: user.id.to_s, email: user.email },
        session: session && {
          id: session.id.to_s, current_url: session.current_url, last_seen_at: time(session.last_seen_at),
          online: session.online?
        },
        cart: cart(cart_for(session, user), items: true),
        recent_orders: recent_orders(user, contact)
      }
    end

    # The session's cart, else the signed-in user's newest cart.
    def cart_for(session, user)
      session&.cart || (user && carts.where(user_id: user.id).order(updated_at: :desc).first)
    end

    def carts
      Spree::Order.where(state: Visitors::CART_STATES, completed_at: nil).where('spree_orders.item_count > 0')
    end

    def cart(order, items: false)
      return unless order && order.line_items.any?

      body = {
        order_number: order.number,
        item_count: order.line_items.sum(:quantity),
        total: money(order.total),
        currency: order.currency
      }
      return body unless items

      body.merge(items: order.line_items.includes(variant: [:images, { product: { master: :images } }]).map do |item|
        { name: item.variant&.name || item.name, quantity: item.quantity, image_url: line_item_image(item) }
      end)
    end

    def line_item_image(item)
      variant = item.variant
      image = variant&.images&.first || variant&.product&.master&.images&.first
      Chat::Urls.image(image)
    end

    def recent_orders(user, contact, limit: 5)
      scope = Spree::Order.complete
      scope = if user
                scope.where(user_id: user.id)
              elsif contact&.email.present?
                scope.where('LOWER(spree_orders.email) = ?', contact.email.downcase)
              else
                return []
              end
      scope.order(completed_at: :desc).limit(limit).map do |order|
        { number: order.number, state: order.state, total: money(order.total), completed_at: time(order.completed_at) }
      end
    end

    # --- Storefront (customer) -------------------------------------------------------------------

    def customer_conversation(conversation)
      return unless conversation

      {
        id: conversation.id.to_s,
        status: conversation.status,
        unread: conversation.customer_unread_count.to_i,
        last_message_at: time(conversation.last_message_at),
        created_at: time(conversation.created_at)
      }
    end

    # What a customer may see of a message: never a note, never a staff member's email.
    def customer_message(message)
      direction = message.direction || legacy_direction(message)
      raise ArgumentError, 'notes are never shown to customers' if direction == 'note'

      {
        id: message.id.to_s,
        direction: direction,
        body: message.body.to_s,
        author: if direction == 'inbound'
                  { kind: 'customer', name: message.sender.respond_to?(:display_name) ? message.sender.display_name : nil }
                else
                  { kind: 'staff', name: Chat.staff_display_name }
                end,
        attachments: attachments(message),
        created_at: time(message.created_at),
        read_at: time(message.read_at)
      }
    end

    # --- Shared ---------------------------------------------------------------------------------

    def time(value)
      value&.utc&.iso8601
    end

    def money(amount)
      format('%.2f', amount.to_d)
    end
  end
end
