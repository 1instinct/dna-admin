module Spree
  module Admin
    # Store product catalogue for in-app purchases (product id -> entitlement).
    class IapProductsController < ResourceController
      private

      def collection
        Spree::IapProduct.order(:platform, :product_id)
      end

      def permitted_resource_params
        return ActionController::Parameters.new unless params[:iap_product].present?

        params.require(:iap_product).permit(:platform, :product_id, :kind, :entitlement, :name, :active, :store_id)
      end
    end
  end
end
