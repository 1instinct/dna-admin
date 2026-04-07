module Spree
  module Api
    module V2
      module Storefront
        module CheckoutControllerDecorator
          def complete
            order = spree_current_order
            user = spree_current_user

            if order_has_consultation_products?(order) && !user&.consultation_passed?
              render json: {
                error: "consultation_required",
                message: "A completed consultation is required to complete this order."
              }, status: :unprocessable_entity and return
            end

            super
          end

          private

          def order_has_consultation_products?(order)
            return false unless order

            order.line_items
              .joins(variant: :product)
              .where(spree_products: { requires_consultation: true })
              .exists?
          end
        end
      end
    end
  end
end

if defined?(Spree::Api::V2::Storefront::CheckoutController)
  Spree::Api::V2::Storefront::CheckoutController.class_eval do
    prepend Spree::Api::V2::Storefront::CheckoutControllerDecorator
  end
end
