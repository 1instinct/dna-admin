module Spree
  module Admin
    # Who is on the storefront now, and what is in shoppers' carts. Sessions come from
    # Visitors::Adapter and carts from the companion gem's SpreeAdminNative::Carts, the same code the
    # admin app's Visitors screen reads.
    #
    #   GET  /admin/visitors                    Live: online sessions (?rows=1 the table rows, for the 15 s refresh)
    #   GET  /admin/visitors/carts              ?status=active|abandoned
    #   GET  /admin/visitors/:id                a session's page timeline and cart
    #   POST /admin/visitors/:id/conversation   starts or opens the visitor's conversation, then the inbox
    # Each also answers JSON.
    class VisitorsController < Spree::Admin::BaseController
      include AdminJsonEndpoints

      PER_PAGE = 50
      CART_STATUSES = %w[active abandoned].freeze

      helper_method :active_minutes

      def index
        @page = [params[:page].to_i, 1].max
        result = adapter.sessions(online: true, page: @page, per_page: PER_PAGE)
        @sessions = result[:records]
        @total = result[:total]
        respond_to do |format|
          format.html do
            render partial: 'live_rows', locals: { sessions: @sessions } if params[:rows].present?
          end
          format.json { render json: { data: @sessions, meta: { total: @total, page: @page } } }
        end
      end

      def carts
        @status = CART_STATUSES.include?(params[:status]) ? params[:status] : 'active'
        @page = [params[:page].to_i, 1].max
        filters = @status == 'abandoned' ? { abandoned: true } : { active_within: active_minutes }
        rows, @total = SpreeAdminNative::Carts.list(page: @page, per_page: PER_PAGE, **filters)
        now = Time.current
        @carts = rows.map { |order| SpreeAdminNative::Carts.as_json(order, url_for: image_url, now: now) }
        @counts = {
          'active' => SpreeAdminNative::Carts.scope(active_within: active_minutes).count,
          'abandoned' => SpreeAdminNative::Carts.scope(abandoned: true).count
        }
        respond_to do |format|
          format.html
          format.json { render json: { data: @carts, meta: { total: @total, page: @page, status: @status } } }
        end
      end

      def show
        @session = adapter.session(params[:id])
        raise ActiveRecord::RecordNotFound unless @session

        record = VisitorSession.find(params[:id])
        @cart = Chat::Presenter.cart(record.cart, items: true)
        respond_to do |format|
          format.html
          format.json { render json: { data: @session.merge(cart_items: @cart && @cart[:items]) } }
        end
      end

      def conversation
        result = adapter.start_conversation(params[:id], try_spree_current_user)
        url = spree.admin_inbox_path(conversation: result[:conversation_id])
        respond_to do |format|
          format.html { redirect_to url }
          format.json { render json: { data: result.merge(url: url) }, status: :created }
        end
      end

      private

      # Authorized against VisitorSession (authorize_admin).
      def model_class
        VisitorSession
      end

      def adapter
        @adapter ||= Visitors::Adapter.new
      end

      # Carts updated within this many minutes are active (the companion gem's setting, 60 by default).
      def active_minutes
        SpreeAdminNative.config.active_cart_minutes || 60
      end

      def image_url
        helpers = Rails.application.routes.url_helpers
        ->(rendition) { helpers.polymorphic_path(rendition) }
      end
    end
  end
end
