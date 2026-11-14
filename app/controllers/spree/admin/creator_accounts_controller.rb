module Spree
  module Admin
    # Creators tab: creator accounts. Edit the revenue share and payout details, suspend or
    # reinstate selling, or revoke the creator role (Creators::Approver.revoke!).
    class CreatorAccountsController < Spree::Admin::BaseController
      PER_PAGE = 50

      before_action :load_account, except: :index

      def index
        @status = Spree::CreatorAccount::STATUSES.include?(params[:status]) ? params[:status] : nil
        scope = Spree::CreatorAccount.includes(:user).order(created_at: :desc, id: :desc)
        scope = scope.where(status: @status) if @status
        @accounts = scope.page(params[:page]).per(PER_PAGE)
      end

      def edit; end

      def update
        if @account.update(params.require(:creator_account).permit(:revenue_share_bps, :payout_email, :payout_notes))
          flash[:success] = 'Creator account updated'
          redirect_to spree.edit_admin_creator_account_path(@account)
        else
          flash.now[:error] = @account.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      def suspend
        @account.update!(status: 'suspended')
        flash[:success] = 'Creator suspended: their portal is closed until reinstated'
        redirect_to spree.edit_admin_creator_account_path(@account)
      end

      def reinstate
        if Creators.creator?(@account.user)
          @account.update!(status: 'active')
          flash[:success] = 'Creator reinstated'
        else
          flash[:error] = 'This user no longer has the creator role; approve a new application instead'
        end
        redirect_to spree.edit_admin_creator_account_path(@account)
      end

      def revoke
        Creators::Approver.revoke!(@account.user)
        flash[:success] = 'Creator role revoked'
        redirect_to spree.edit_admin_creator_account_path(@account)
      end

      private

      def model_class
        Spree::CreatorAccount
      end

      def load_account
        @account = Spree::CreatorAccount.find(params[:id])
      end
    end
  end
end
