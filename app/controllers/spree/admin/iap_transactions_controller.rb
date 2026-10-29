module Spree
  module Admin
    # "IAP Orders": verified App Store / Google Play transactions.
    class IapTransactionsController < Spree::Admin::BaseController
      FILTERS = %i[platform status environment product_id].freeze

      def index
        scope = Spree::IapTransaction.includes(:user, :iap_product).newest_first
        FILTERS.each { |f| scope = scope.where(f => params[f]) if params[f].present? }
        if params[:email].present?
          users = Spree.user_class.where("#{Spree.user_class.table_name}.email ILIKE ?",
                                         "%#{Spree::IapTransaction.sanitize_sql_like(params[:email].strip)}%")
          scope = scope.where(user_id: users.select(:id))
        end
        scope = scope.where('spree_iap_transactions.purchased_at >= ?', parse_date(params[:from]).beginning_of_day) if parse_date(params[:from])
        scope = scope.where('spree_iap_transactions.purchased_at <= ?', parse_date(params[:to]).end_of_day) if parse_date(params[:to])
        @transactions = scope.page(params[:page]).per(params[:per_page].presence || 25)
      end

      def show
        @transaction = Spree::IapTransaction.find(params[:id])
        @notifications = @transaction.iap_notifications.newest_first
        @entitlements = Spree::Entitlement.where(iap_transaction_id: @transaction.id)
        @audit_logs = @transaction.audit_logs.includes(:admin_user).order(created_at: :desc)
      end

      def revoke
        transaction = Spree::IapTransaction.find(params[:id])
        note = params[:note].to_s.strip
        if note.empty?
          flash[:error] = 'A note is required to revoke a purchase.'
        else
          ::Iap::AdminRevocation.new(transaction, admin: try_spree_current_user, note: note).call
          flash[:success] = 'Purchase revoked.'
        end
        redirect_to spree.admin_iap_transaction_path(transaction)
      end

      private

      def model_class
        Spree::IapTransaction
      end

      def parse_date(value)
        value.present? ? Date.parse(value.to_s) : nil
      rescue ArgumentError
        nil
      end
    end
  end
end
