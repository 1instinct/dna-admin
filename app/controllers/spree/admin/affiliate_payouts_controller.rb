module Spree
  module Admin
    # Affiliate payouts. Money moves outside the app; recording a payout (with the payment's
    # reference) marks the account's approved commissions paid.
    class AffiliatePayoutsController < Spree::Admin::BaseController
      PER_PAGE = 50

      def index
        AffiliateCommission.sweep!
        @payouts = AffiliatePayout.includes(:affiliate_account).order(paid_at: :desc, id: :desc).page(params[:page]).per(PER_PAGE)
        @payable = AffiliateCommission.approved.group(:affiliate_account_id, :currency).sum(:amount)
        @payable_accounts = AffiliateAccount.where(id: @payable.keys.map(&:first)).index_by(&:id)
      end

      def new
        @account = AffiliateAccount.find(params[:affiliate_account_id])
        AffiliateCommission.sweep!
        @payable = Affiliates::Payouts.payable(@account)
        @currency = params[:currency].presence || @payable.keys.first || @account.currency
      end

      def create
        account = AffiliateAccount.find(params[:affiliate_account_id])
        payout = Affiliates::Payouts.create!(account: account, reference: params[:reference], note: params[:note],
                                             currency: params[:currency])
        flash[:success] = "Payout of #{payout.amount} #{payout.currency} recorded for #{account.code}"
        redirect_to spree.admin_affiliate_payouts_path
      rescue Affiliates::Payouts::Error => e
        flash[:error] = e.message
        redirect_to spree.new_admin_affiliate_payout_path(affiliate_account_id: account.id)
      end

      private

      def model_class
        AffiliatePayout
      end
    end
  end
end
