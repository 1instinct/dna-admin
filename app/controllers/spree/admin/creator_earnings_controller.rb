module Spree
  module Admin
    # Creators tab: the earnings ledger. Filters: state, creator account. Pending earnings past
    # their hold become payable when the page is read.
    class CreatorEarningsController < Spree::Admin::BaseController
      PER_PAGE = 50

      def index
        Spree::CreatorEarning.sweep!
        @state = Spree::CreatorEarning::STATES.include?(params[:state]) ? params[:state] : nil
        @account_id = params[:creator_account_id].presence&.to_i
        scope = Spree::CreatorEarning.includes(:order, :line_item, creator_account: :user).order(created_at: :desc, id: :desc)
        scope = scope.where(state: @state) if @state
        scope = scope.where(creator_account_id: @account_id) if @account_id
        @earnings = scope.page(params[:page]).per(PER_PAGE)
        @accounts = Spree::CreatorAccount.includes(:user).order(:id)
      end

      private

      def model_class
        Spree::CreatorEarning
      end
    end
  end
end
