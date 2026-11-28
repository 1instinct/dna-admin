module Spree
  module Admin
    # The customer inbox: conversations, the chat and the customer's context in three panes. Every
    # read and write goes through Chat::InboxAdapter (Chat::Conversations and Chat::Presenter), the
    # same code the admin app's inbox uses, so both show the same conversations the same way.
    #
    # HTML: GET /admin/inbox (?conversation=<id> opens one).
    # JSON (the page's script, session auth with the CSRF token):
    #   GET   /admin/inbox/summary                          { open, unassigned, unread }
    #   GET   /admin/inbox/conversations                    ?filter=open|mine|unassigned|closed&q=&updated_since=&page=
    #   GET   /admin/inbox/conversations/:id                the conversation and its customer context
    #   GET   /admin/inbox/conversations/:id/messages       ?after=<id> (polling) or ?before=<id> (older)
    #   POST  /admin/inbox/conversations/:id/messages       body, note, attachments[] (multipart)
    #   PATCH /admin/inbox/conversations/:id                assignee_id (an id, "me" or blank), status, snooze
    #   POST  /admin/inbox/conversations/:id/read
    class InboxController < Spree::Admin::BaseController
      include AdminJsonEndpoints

      FILTERS = {
        'open' => { status: 'open' },
        'mine' => { status: 'open', assignee: 'me' },
        'unassigned' => { status: 'open', assignee: 'unassigned' },
        'closed' => { status: 'closed' }
      }.freeze
      MAX_ATTACHMENTS = 10
      MAX_ATTACHMENT_BYTES = 25.megabytes

      before_action :load_conversation, only: %i[show messages reply update read]

      rescue_from SpreeAdminNative::AdapterInvalid, Chat::Conversations::Invalid do |e|
        render_json_error('invalid', e.message)
      end

      def index
        @staff = staff_members
        @snooze_options = Chat::SnoozePresets.options
        @summary = adapter.summary(try_spree_current_user)
      end

      def summary
        render json: { data: adapter.summary(try_spree_current_user).merge(me: me_json) }
      end

      def conversations
        filter = FILTERS.fetch(params[:filter].presence || 'open') do
          return render_json_error('invalid', "filter must be one of #{FILTERS.keys.join(', ')}")
        end
        now = Time.current
        result = adapter.conversations(filter.merge(
          q: params[:q].presence, updated_since: params[:updated_since].presence, page: params[:page],
          per_page: params[:per_page], admin: try_spree_current_user
        ))
        render json: { data: result[:records], meta: { total: result[:total], page: [params[:page].to_i, 1].max, now: now.utc.iso8601(3) } }
      end

      def show
        render json: { data: adapter.conversation(@conversation), customer_context: adapter.customer_context(@conversation) }
      end

      def messages
        list = adapter.messages(@conversation, before: params[:before].presence, after: params[:after].presence,
                                               limit: params[:limit].presence)
        render json: { data: list }
      end

      def reply
        blobs = uploaded_blobs
        return if performed?

        message = adapter.reply(@conversation, try_spree_current_user,
                                body: params[:body].to_s, attachments: blobs,
                                note: ActiveModel::Type::Boolean.new.cast(params[:note]) == true)
        render json: { data: message, conversation: adapter.conversation(@conversation.reload) }, status: :created
      end

      def update
        attrs = {}
        if params.key?(:assignee_id)
          value = params[:assignee_id].to_s
          attrs[:assignee_id] = value == 'me' ? try_spree_current_user&.id : value.presence
        end
        attrs[:status] = params[:status] if params[:status].present?
        if params[:snooze].present?
          time = Chat::SnoozePresets.until_time(params[:snooze])
          return render_json_error('invalid', "snooze must be one of #{Chat::SnoozePresets::LABELS.keys.join(', ')}") unless time

          attrs[:snoozed_until] = time
        end
        conversation = adapter.update(@conversation, try_spree_current_user, attrs)
        render json: { data: conversation, customer_context: adapter.customer_context(@conversation.reload) }
      end

      def read
        render json: { data: adapter.mark_read(@conversation, try_spree_current_user) }
      end

      private

      # Authorized against ThreadTable (authorize_admin), like the older threads pages.
      def model_class
        ThreadTable
      end

      def adapter
        @adapter ||= Chat::InboxAdapter.new
      end

      def load_conversation
        @conversation = ThreadTable.conversations.find(params[:id])
      end

      def staff_members
        user_class = Spree.user_class
        user_class.joins(:spree_roles).where(spree_roles: { name: 'admin' }).distinct.order(:email).to_a
      end

      def me_json
        user = try_spree_current_user
        user && { id: user.id.to_s, email: user.email }
      end

      # Uploaded files as blobs for Chat::Conversations (at most 10, 25 MB each).
      def uploaded_blobs
        files = Array(params[:attachments]).select { |f| f.respond_to?(:original_filename) && f.respond_to?(:read) }
        if files.size > MAX_ATTACHMENTS
          render_json_error('invalid', "Attach up to #{MAX_ATTACHMENTS} files at a time.")
          return []
        end
        if (big = files.find { |f| f.size > MAX_ATTACHMENT_BYTES })
          render_json_error('too_large', "#{big.original_filename} is larger than 25 MB.", 413)
          return []
        end

        files.map do |file|
          ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename,
                                                 content_type: file.content_type.presence)
        end
      end
    end
  end
end
