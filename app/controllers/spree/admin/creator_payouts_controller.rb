module Spree
  module Admin
    # Creators tab: payouts. Money moves outside the app; recording a payout (with the payment's
    # reference) marks the account's payable earnings paid (Creators::Payouts).
    class CreatorPayoutsController < Spree::Admin::BaseController
      PER_PAGE = 50

      def index
        Spree::CreatorEarning.sweep!
        @payouts = Spree::CreatorPayout.includes(creator_account: :user).order(paid_at: :desc, id: :desc)
                                       .page(params[:page]).per(PER_PAGE)
        @payable = Spree::CreatorEarning.payable.group(:creator_account_id, :currency).sum(:amount)
        @payable_accounts = Spree::CreatorAccount.includes(:user).where(id: @payable.keys.map(&:first)).index_by(&:id)
      end

      def new
        @account = Spree::CreatorAccount.find(params[:creator_account_id])
        @payable = Creators::Payouts.payable(@account)
        @currency = params[:currency].presence || @payable.keys.first ||
                    Spree::Store.default.default_currency.presence || Spree::Config[:currency]
      end

      def create
        account = Spree::CreatorAccount.find(params[:creator_account_id])
        payout = Creators::Payouts.create!(account: account, reference: params[:reference], note: params[:note],
                                           currency: params[:currency])
        flash[:success] = "Payout of #{payout.amount} #{payout.currency} recorded for #{account.user&.email}"
        redirect_to spree.admin_creator_payouts_path
      rescue Creators::Payouts::Error => e
        flash[:error] = e.message
        redirect_to spree.new_admin_creator_payout_path(creator_account_id: account.id, currency: params[:currency])
      end

      private

      def model_class
        Spree::CreatorPayout
      end
    end
  end
end
