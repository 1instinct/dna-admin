module Chat
  # The admin app's inbox (companion gem 0.7, /api/admin_native/v1/inbox) over this app's
  # conversations: plain hashes in the gem's shapes (Chat::Presenter), registered as
  # SpreeAdminNative.config.inbox_adapter in config/initializers/chat.rb.
  #
  # A conversation argument may be what #conversation returned (a hash with an id), a ThreadTable
  # or an id. Refused input raises SpreeAdminNative::AdapterInvalid (the gem's 422); an unknown
  # conversation raises ActiveRecord::RecordNotFound (404).
  class InboxAdapter < SpreeAdminNative::Inbox::Adapter
    STATUS_FILTERS = %w[open snoozed closed all].freeze
    ASSIGNEE_FILTERS = %w[me unassigned any].freeze
    PER_PAGE = 25
    PER_PAGE_MAX = 100
    MESSAGES_LIMIT = 50
    MESSAGES_LIMIT_MAX = 200

    def available?
      ThreadTable.table_exists? && ThreadTable.column_names.include?('staff_unread_count') && Contact.table_exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    # filters: status (open|snoozed|closed|all, default open), assignee (me|unassigned|any,
    # default any; me needs admin), q (contact name or email, or message text), updated_since
    # (ISO time), page, per_page, admin (the signed-in staff user, for assignee=me).
    # Returns { records: [conversation], total: } newest activity first.
    def conversations(filters = {})
      filters = normalize(filters)
      Chat::Conversations.wake_due!
      scope = ThreadTable.conversations.includes(:contact, :assignee)

      status = filters[:status].presence || 'open'
      raise Chat::Conversations::Invalid, "status must be one of #{STATUS_FILTERS.join(', ')}" unless STATUS_FILTERS.include?(status)

      scope = scope.where(status: status) unless status == 'all'
      scope = filter_assignee(scope, filters[:assignee].presence || 'any', filters[:admin])
      scope = search(scope, filters[:q]) if filters[:q].present?
      if filters[:updated_since].present?
        since = filters[:updated_since].is_a?(Time) ? filters[:updated_since] : parse_time(filters[:updated_since])
        raise Chat::Conversations::Invalid, 'updated_since must be an ISO 8601 time' unless since

        scope = scope.where('thread_tables.updated_at > ?', since)
      end

      per_page = (filters[:per_page].presence || PER_PAGE).to_i.clamp(1, PER_PAGE_MAX)
      page = [filters[:page].to_i, 1].max
      total = scope.count
      records = scope.recent_activity_first.offset((page - 1) * per_page).limit(per_page).to_a
      lasts = last_messages(records.map(&:id))
      { records: records.map { |c| Chat::Presenter.conversation(c, last_message: lasts[c.id]) }, total: total }
    rescue Chat::Conversations::Invalid => e
      raise SpreeAdminNative::AdapterInvalid, e.message
    end

    # The conversation hash, or nil.
    def conversation(id)
      record = ThreadTable.conversations.includes(:contact, :assignee).find_by(id: id_of(id))
      record && Chat::Presenter.conversation(record)
    end

    # Oldest first, notes included. after (a message id) for polling, before for scrolling back;
    # limit 50 by default, 200 at most. Without after, the newest messages (before the given id).
    def messages(conversation, before: nil, after: nil, limit: nil)
      record = find!(conversation)
      limit = (limit.presence || MESSAGES_LIMIT).to_i.clamp(1, MESSAGES_LIMIT_MAX)
      scope = record.messages.with_attached_attachments.includes(:sender, :author, :thread_table)
      scope = scope.where('messages.id < ?', before.to_i) if before.present?
      list = if after.present?
               scope.where('messages.id > ?', after.to_i).reorder(id: :asc).limit(limit).to_a
             else
               scope.reorder(id: :desc).limit(limit).to_a.reverse
             end
      list.map { |m| Chat::Presenter.message(m) }
    rescue Chat::Conversations::Invalid => e
      raise SpreeAdminNative::AdapterInvalid, e.message
    end

    # A reply on the conversation's channel, or a staff note with note: true. Returns the message.
    def reply(conversation, admin, body:, attachments: [], note: false)
      record = find!(conversation)
      message = if note
                  Chat::Conversations.note(record, admin, body: body, attachments: attachments)
                else
                  Chat::Conversations.post_outbound(record, admin, body: body, attachments: attachments)
                end
      Chat::Presenter.message(message.reload)
    rescue Chat::Conversations::Invalid => e
      raise SpreeAdminNative::AdapterInvalid, e.message
    end

    # attrs: status, assignee_id (nil unassigns), snoozed_until. Returns the conversation.
    def update(conversation, _admin, attrs)
      record = find!(conversation)
      Chat::Conversations.update(record, attrs)
      Chat::Presenter.conversation(record.reload)
    rescue Chat::Conversations::Invalid => e
      raise SpreeAdminNative::AdapterInvalid, e.message
    end

    def mark_read(conversation, _admin)
      record = find!(conversation)
      Chat::Conversations.mark_read_by_staff(record)
      Chat::Presenter.conversation(record.reload)
    end

    # { open:, unassigned:, unread: } (unread: conversations, not closed, with unread messages).
    def summary(_admin = nil)
      Chat::Conversations.counters
    end

    def customer_context(conversation)
      Chat::Presenter.customer_context(find!(conversation))
    end

    private

    def normalize(filters)
      filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
      (filters || {}).to_h.symbolize_keys
    end

    def filter_assignee(scope, assignee, admin)
      raise Chat::Conversations::Invalid, "assignee must be one of #{ASSIGNEE_FILTERS.join(', ')}" unless ASSIGNEE_FILTERS.include?(assignee)

      case assignee
      when 'me'
        raise Chat::Conversations::Invalid, 'assignee=me needs the signed-in admin' unless admin

        scope.where(assignee_id: admin.id)
      when 'unassigned' then scope.where(assignee_id: nil)
      else scope
      end
    end

    # Contact name, full name or email, or the text of any message (notes included: staff search).
    def search(scope, query)
      term = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)}%"
      contacts = Contact.where('LOWER(contacts.name) LIKE :t OR LOWER(contacts.full_name) LIKE :t OR LOWER(contacts.email) LIKE :t', t: term)
                        .select(:id)
      bodies = Message.where('LOWER(messages.message) LIKE ?', term).select(:thread_table_id)
      scope.where(contact_id: contacts).or(scope.where(id: bodies))
    end

    # The last message the customer can see, for each conversation, in one query.
    def last_messages(ids)
      return {} if ids.empty?

      last_ids = Message.visible_to_customer.where(thread_table_id: ids).group(:thread_table_id).maximum(:id)
      Message.where(id: last_ids.values).index_by(&:thread_table_id)
    end

    def find!(conversation)
      return conversation if conversation.is_a?(ThreadTable)

      ThreadTable.conversations.find(id_of(conversation))
    end

    def id_of(conversation)
      case conversation
      when ThreadTable then conversation.id
      when Hash then conversation[:id] || conversation['id']
      else conversation
      end
    end

    def parse_time(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      begin
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
