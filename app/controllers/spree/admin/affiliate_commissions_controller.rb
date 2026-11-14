module Spree
  module Admin
    # Affiliate commissions, newest first. Filters: state, affiliate, created-at date range.
    # A pending or approved commission can be voided by hand.
    class AffiliateCommissionsController < Spree::Admin::BaseController
      PER_PAGE = 50

      def index
        AffiliateCommission.sweep!
        @filters = params.permit(:state, :affiliate_account_id, :from, :to).to_h.symbolize_keys
        scope = AffiliateCommission.includes(:affiliate_account, :order).order(created_at: :desc, id: :desc)
        scope = scope.where(state: @filters[:state]) if AffiliateCommission::STATES.include?(@filters[:state])
        scope = scope.where(affiliate_account_id: @filters[:affiliate_account_id].to_i) if @filters[:affiliate_account_id].present?
        from = parse_date(@filters[:from])
        to = parse_date(@filters[:to])
        scope = scope.where('affiliate_commissions.created_at >= ?', from.beginning_of_day) if from
        scope = scope.where('affiliate_commissions.created_at <= ?', to.end_of_day) if to
        @commissions = scope.page(params[:page]).per(PER_PAGE)
        @accounts = AffiliateAccount.order(:code).pluck(:code, :id)
      end

      def void
        commission = AffiliateCommission.find(params[:id])
        if commission.pending? || commission.approved?
          commission.update!(state: 'void')
          flash[:success] = 'Commission voided'
        else
          flash[:error] = "A #{commission.state} commission can't be voided"
        end
        redirect_back fallback_location: spree.admin_affiliate_account_commissions_path
      end

      private

      def model_class
        AffiliateCommission
      end

      def parse_date(value)
        Date.iso8601(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
