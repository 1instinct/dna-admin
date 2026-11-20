module Spree
  module Admin
    # Lock (POST) / unlock (DELETE) /admin/users/:user_id/account_lock.
    class AccountLocksController < Spree::Admin::BaseController
      before_action :load_user

      def create
        Profiles::Moderation.lock(@user)
        flash[:success] = 'Account locked'
      rescue Profiles::Moderation::Refused => e
        flash[:error] = e.message
      ensure
        redirect_to spree.edit_admin_user_path(@user) unless performed?
      end

      def destroy
        Profiles::Moderation.unlock(@user)
        flash[:success] = 'Account unlocked'
        redirect_to spree.edit_admin_user_path(@user)
      end

      private

      def model_class
        Spree.user_class
      end

      def load_user
        @user = Spree.user_class.find(params[:user_id])
      end
    end
  end
end
