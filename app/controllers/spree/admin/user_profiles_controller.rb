module Spree
  module Admin
    # Hide / unhide a profile from the Profile panel on the admin user page.
    class UserProfilesController < Spree::Admin::BaseController
      before_action :load_profile

      def hide
        Profiles::Moderation.hide(@profile, reason: params[:reason].presence || 'Hidden by an admin')
        flash[:success] = 'Profile hidden'
        redirect_to spree.edit_admin_user_path(@profile.user_id)
      end

      def unhide
        Profiles::Moderation.unhide(@profile)
        flash[:success] = 'Profile visible again'
        redirect_to spree.edit_admin_user_path(@profile.user_id)
      end

      private

      def model_class
        Spree::UserProfile
      end

      def load_profile
        @profile = Spree::UserProfile.find(params[:id])
      end
    end
  end
end
