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

      # POST /admin/creator_earnings/:id/void: voids a pending or payable earning (void_reason admin).
      def void
        earning = Spree::CreatorEarning.find(params[:id])
        if earning.void_by_admin!
          flash[:success] = "Earning #{earning.id} voided."
        else
          flash[:error] = "Earning #{earning.id} is #{earning.state} and cannot be voided."
        end
        redirect_to spree.admin_creator_earnings_path
      end

      private

      def model_class
        Spree::CreatorEarning
      end
    end
  end
end
