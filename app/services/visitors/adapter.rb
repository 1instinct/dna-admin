module Visitors
  # The admin app's visitors (companion gem 0.7, /api/admin_native/v1/visitors) over this app's
  # sessions: plain hashes, registered as SpreeAdminNative.config.visitors_adapter in
  # config/initializers/chat.rb.
  #
  # A session argument may be what #session returned (a hash with an id), a VisitorSession or an
  # id; an unknown one raises ActiveRecord::RecordNotFound.
  class Adapter < SpreeAdminNative::Visitors::Adapter
    PER_PAGE = 25
    PER_PAGE_MAX = 100

    def available?
      VisitorSession.table_exists? && VisitorPageView.table_exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    # filters: online (true: seen in the last 2 minutes; false: not; unset: all), page, per_page.
    # Returns { records: [session], total: } most recently seen first.
    def sessions(filters = {})
      filters = normalize(filters)
      scope = VisitorSession.includes(:contact, order: :line_items)
      case boolean(filters[:online])
      when true then scope = scope.online
      when false then scope = scope.offline
      end
      per_page = (filters[:per_page].presence || PER_PAGE).to_i.clamp(1, PER_PAGE_MAX)
      page = [filters[:page].to_i, 1].max
      total = scope.count
      records = scope.recent_first.offset((page - 1) * per_page).limit(per_page).to_a
      conversations = conversation_ids(records.map(&:contact_id))
      { records: records.map { |s| present(s, conversations[s.contact_id]) }, total: total }
    end

    # The session hash plus pages: [{ url, title, at }] (newest first, the last 50), or nil.
    def session(id)
      record = VisitorSession.includes(:contact, order: :line_items).find_by(id: id_of(id))
      return unless record

      present(record, conversation_ids([record.contact_id])[record.contact_id]).merge(
        pages: record.pages.limit(Visitors.config.page_view_limit).map do |view|
          { url: view.url, title: view.title, at: Chat::Presenter.time(view.created_at) }
        end
      )
    end

    # The visitor's open conversation, or a new one assigned to the staff member who started it.
    # Returns { conversation_id }.
    def start_conversation(session, admin)
      record = find!(session)
      conversation, created = Chat::Conversations.find_or_create(record.contact, channel: 'web', visitor_session: record)
      if created
        conversation.update!(assignee: admin) if admin && Chat::Conversations.admin?(admin)
      elsif conversation.visitor_session_id != record.id
        conversation.update!(visitor_session: record)
      end
      { conversation_id: conversation.id.to_s }
    end

    private

    def present(record, conversation_id)
      contact = record.contact
      utm = { source: record.utm_source, medium: record.utm_medium, campaign: record.utm_campaign }
      {
        id: record.id.to_s,
        contact: contact && { id: contact.id.to_s, name: contact.display_name, email: contact.email.presence },
        user_id: contact&.user_id&.to_s,
        current_url: record.current_url,
        current_title: record.current_title,
        referrer: record.referrer,
        utm: utm.values.any?(&:present?) ? utm : nil,
        device: record.device || 'desktop',
        country: record.country,
        started_at: Chat::Presenter.time(record.started_at),
        last_seen_at: Chat::Presenter.time(record.last_seen_at),
        online: record.online?,
        page_views: record.page_views.to_i,
        cart: Chat::Presenter.cart(record.cart),
        conversation_id: conversation_id&.to_s
      }
    end

    # Each contact's current (not closed) conversation id.
    def conversation_ids(contact_ids)
      return {} if contact_ids.empty?

      ThreadTable.conversations.not_closed.where(contact_id: contact_ids)
                 .order(Arel.sql('thread_tables.last_message_at ASC NULLS FIRST, thread_tables.id ASC'))
                 .pluck(:contact_id, :id).to_h
    end

    def normalize(filters)
      filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
      (filters || {}).to_h.symbolize_keys
    end

    def boolean(value)
      case value.to_s.downcase
      when 'true', '1', 'yes' then true
      when 'false', '0', 'no' then false
      end
    end

    def find!(session)
      return session if session.is_a?(VisitorSession)

      VisitorSession.find(id_of(session))
    end

    def id_of(session)
      case session
      when VisitorSession then session.id
      when Hash then session[:id] || session['id']
      else session
      end
    end
  end
end
