module Chat
  # Everything that changes a customer conversation goes through here, so the counters, statuses
  # and timestamps stay consistent whoever calls (the storefront API, the admin app adapter, a
  # future inbound channel). Counter changes take the conversation's row lock. The older archived
  # flag follows the status (closed is archived).
  #
  #   conversation = Chat::Conversations.find_or_create(contact, channel: 'web')
  #   Chat::Conversations.post_inbound(conversation, body: 'Is this in stock?')
  #   Chat::Conversations.post_outbound(conversation, admin, body: 'Yes!')
  #   Chat::Conversations.note(conversation, admin, body: 'VIP customer')
  #   Chat::Conversations.mark_read_by_staff(conversation)
  #   Chat::Conversations.assign(conversation, admin) / snooze(conversation, 2.hours.from_now) / close(conversation)
  module Conversations
    class Invalid < ArgumentError; end

    module_function

    # The contact's newest conversation that isn't closed.
    def current_for(contact)
      return unless contact&.persisted?

      ThreadTable.conversations.not_closed.where(contact_id: contact.id).recent_activity_first.first
    end

    # The contact's current conversation, or a new open one on the channel. created is true when
    # a new one was made.
    def find_or_create(contact, channel: 'web', visitor_session: nil, subject: nil)
      existing = current_for(contact)
      return [existing, false] if existing

      conversation = ThreadTable.create!(
        contact: contact, status: 'open', channel: channel.to_s, subject: subject.presence,
        visitor_session: visitor_session, archived: false, stale: false
      )
      [conversation, true]
    end

    # A message from the customer: reopens a snoozed or closed conversation and counts it unread
    # for staff. The admin app is told after commit.
    def post_inbound(conversation, body:, channel: nil, external_id: nil, attachments: [], visitor_session: nil)
      body = clean_body(body, attachments: attachments)
      message = nil
      conversation.with_lock do
        message = conversation.messages.create!(
          direction: 'inbound', channel: (channel || conversation.channel || 'web').to_s, message: body,
          sender: conversation.contact, receiver: conversation.assignee, external_id: external_id,
          is_received: true, is_read: false
        )
        attach(message, attachments)
        conversation.status = 'open'
        conversation.archived = false
        conversation.snoozed_until = nil
        conversation.last_message_at = message.created_at
        conversation.staff_unread_count += 1
        conversation.visitor_session = visitor_session if visitor_session
        conversation.save!
      end
      conversation.contact&.update_column(:last_seen_at, Time.current)
      notify_inbound(conversation, message)
      message
    end

    # A staff reply: counted unread for the customer and delivered on the conversation's channel
    # after commit.
    def post_outbound(conversation, admin, body:, attachments: [])
      body = clean_body(body, attachments: attachments)
      message = nil
      conversation.with_lock do
        message = conversation.messages.create!(
          direction: 'outbound', channel: (conversation.channel || 'web').to_s, message: body,
          sender: admin, receiver: conversation.contact, author: admin, delivery_status: 'sent',
          is_received: false, is_read: false
        )
        attach(message, attachments)
        conversation.last_message_at = message.created_at
        conversation.customer_unread_count += 1
        conversation.save!
      end
      Chat::Channels.deliver(message)
      message
    end

    # A staff-only note: never delivered and never shown to the customer. It bumps updated_at
    # (so the admin app's polling sees it) but not last_message_at.
    def note(conversation, admin, body:, attachments: [])
      body = clean_body(body, attachments: attachments)
      message = nil
      conversation.with_lock do
        message = conversation.messages.create!(
          direction: 'note', channel: (conversation.channel || 'web').to_s, message: body,
          sender: admin, receiver: nil, author: admin, is_received: false, is_read: true
        )
        attach(message, attachments)
        conversation.touch
      end
      message
    end

    # Every inbound message read by staff.
    def mark_read_by_staff(conversation, now: Time.current)
      conversation.with_lock do
        conversation.messages.inbound.unread.update_all(read_at: now, is_read: true, updated_at: now)
        if conversation.staff_unread_count.positive?
          conversation.staff_unread_count = 0
          conversation.save!
        end
      end
      conversation
    end

    # Every staff reply read by the customer.
    def mark_read_by_customer(conversation, now: Time.current)
      conversation.with_lock do
        conversation.messages.outbound.unread.update_all(read_at: now, is_read: true, delivery_status: 'delivered',
                                                         updated_at: now)
        if conversation.customer_unread_count.positive?
          conversation.customer_unread_count = 0
          conversation.save!
        end
      end
      conversation
    end

    # Staff replies the widget has now fetched count as delivered.
    def mark_delivered(messages, now: Time.current)
      ids = messages.select { |m| m.direction == 'outbound' && m.delivery_status == 'sent' }.map(&:id)
      Message.where(id: ids).update_all(delivery_status: 'delivered', updated_at: now) if ids.any?
    end

    def assign(conversation, assignee)
      raise Invalid, 'assignee must be an admin' if assignee && !admin?(assignee)

      conversation.update!(assignee: assignee)
      conversation
    end

    def snooze(conversation, until_time)
      until_time = parse_time(until_time)
      raise Invalid, 'snoozed_until must be in the future' unless until_time && until_time > Time.current

      conversation.update!(status: 'snoozed', snoozed_until: until_time, archived: false)
      conversation
    end

    def close(conversation)
      conversation.update!(status: 'closed', snoozed_until: nil, archived: true)
      conversation
    end

    def reopen(conversation)
      conversation.update!(status: 'open', snoozed_until: nil, archived: false)
      conversation
    end

    # { status?, assignee_id?, snoozed_until? } from the admin app (only the keys it sent), applied
    # together. snoozed_until alone snoozes, or with null wakes a snoozed conversation; status
    # 'snoozed' needs a time.
    def update(conversation, attrs)
      attrs = (attrs || {}).to_h.symbolize_keys
      ThreadTable.transaction do
        if attrs.key?(:assignee_id)
          id = attrs[:assignee_id].presence
          assignee = id && Spree::User.find_by(id: id)
          raise Invalid, 'assignee not found' if id && !assignee

          assign(conversation, assignee)
        end

        status = attrs[:status].presence&.to_s
        raise Invalid, "status must be one of #{ThreadTable::STATUSES.join(', ')}" if status && !ThreadTable::STATUSES.include?(status)

        if status == 'snoozed' || (status.nil? && attrs[:snoozed_until].present?)
          snooze(conversation, attrs[:snoozed_until])
        elsif status.nil? && attrs.key?(:snoozed_until) && conversation.status == 'snoozed'
          reopen(conversation)
        elsif status == 'closed'
          close(conversation)
        elsif status == 'open'
          reopen(conversation)
        end
      end
      conversation
    end

    # Snoozed conversations whose time has come are open again.
    def wake_due!(now = Time.current)
      ThreadTable.conversations.where(status: 'snoozed').where('snoozed_until <= ?', now)
                 .update_all(status: 'open', snoozed_until: nil, updated_at: now)
    end

    # { open:, unassigned:, unread: } for the admin app's badges. unread counts conversations
    # (not closed) with unread customer messages.
    def counters
      wake_due!
      open = ThreadTable.conversations.where(status: 'open')
      {
        open: open.count,
        unassigned: open.where(assignee_id: nil).count,
        unread: ThreadTable.conversations.not_closed.where('staff_unread_count > 0').count
      }
    end

    # 1 to 4000 characters; empty is fine when the message carries attachments.
    def clean_body(body, attachments: nil)
      text = body.to_s.delete("\u0000").strip
      raise Invalid, 'body must be 1 to 4000 characters' if text.length > Message::BODY_MAX
      raise Invalid, 'body must be 1 to 4000 characters' if text.empty? && Array(attachments).compact.empty?

      text
    end

    # Signed ids (from an upload) or blobs.
    def attach(message, attachments)
      blobs = Array(attachments).compact.map do |item|
        blob = item.is_a?(ActiveStorage::Blob) ? item : ActiveStorage::Blob.find_signed(item.to_s)
        raise Invalid, 'attachment not found' unless blob

        blob
      end
      message.attachments.attach(blobs) if blobs.any?
    end

    # The admin app's push (companion gem: throttled per conversation, queued through ActiveJob).
    def notify_inbound(conversation, message)
      SpreeAdminNative::Inbox.notify_inbound(Chat::Presenter.conversation(conversation, last_message: message),
                                             Chat::Presenter.message(message))
    rescue StandardError => e
      Rails.logger.error("[chat] admin push for conversation #{conversation.id} failed: #{e.class}")
    end

    def admin?(user)
      user.respond_to?(:has_spree_role?) ? user.has_spree_role?('admin') : true
    end

    def parse_time(value)
      return value if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
