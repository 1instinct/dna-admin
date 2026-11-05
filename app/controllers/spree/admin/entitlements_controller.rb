module Spree
  module Admin
    # Manual revocation of a user's entitlement: revokes every transaction that
    # currently grants it, each with the admin's note in the audit log.
    class EntitlementsController < Spree::Admin::BaseController
      def revoke
        entitlement = Spree::Entitlement.find(params[:id])
        note = params[:note].to_s.strip
        granting = Spree::IapTransaction.where(user_id: entitlement.user_id).includes(:iap_product)
                                        .select { |t| t.entitlement_key == entitlement.key && t.grants_access? }
        if note.empty?
          flash[:error] = 'A note is required to revoke an entitlement.'
        elsif granting.empty?
          flash[:error] = 'No purchase currently grants this entitlement.'
        else
          admin = try_spree_current_user
          granting.each { |t| ::Iap::AdminRevocation.new(t, admin: admin, note: note).call }
          flash[:success] = "Entitlement #{entitlement.key} revoked."
        end
        redirect_to spree.edit_admin_user_path(entitlement.user_id)
      end

      private

      def model_class
        Spree::Entitlement
      end
    end
  end
end
