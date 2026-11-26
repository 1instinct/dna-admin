module Spree
  module Admin
    # Ownership panel on the admin user page (spree/admin/users/_digital_ownerships):
    #   POST /admin/users/:user_id/digital_ownerships { variant }   grant (variant SKU or id; the
    #        variant must have a published asset), source "grant"
    #   POST /admin/users/:user_id/digital_ownerships/:id/revoke { reason }
    # Admin only (authorize_admin checks :admin on DigitalOwnership).
    class DigitalOwnershipsController < Spree::Admin::BaseController
      before_action :load_user

      def create
        variant = find_variant(params[:variant].to_s.strip)
        if variant&.digital?
          Spree::DigitalOwnership.grant!(user: @user, variant: variant, source: 'grant')
          flash[:success] = "Granted #{variant.descriptive_name}"
        else
          flash[:error] = 'No variant with a published digital asset matches that SKU or id'
        end
        redirect_to location
      end

      def revoke
        ownership = Spree::DigitalOwnership.where(user_id: @user.id).find(params[:id])
        ownership.revoke!(params[:reason].to_s.strip.presence || 'admin_revoked')
        flash[:success] = 'Ownership revoked'
        redirect_to location
      end

      private

      def model_class
        Spree::DigitalOwnership
      end

      def load_user
        @user = Spree.user_class.find(params[:user_id])
      end

      def find_variant(value)
        return nil if value.empty?

        Spree::Variant.find_by(sku: value) || (value.match?(/\A\d+\z/) ? Spree::Variant.find_by(id: value) : nil)
      end

      def location
        spree.edit_admin_user_url(@user)
      end
    end
  end
end
