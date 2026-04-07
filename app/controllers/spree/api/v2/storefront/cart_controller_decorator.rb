module Spree
  module Api
    module V2
      module Storefront
        module CartControllerDecorator
          def add_item
            variant = Spree::Variant.find_by(id: params[:variant_id])
            if variant && !variant.product.can_purchase?(spree_current_user)
              render json: {
                error: "consultation_required",
                message: "A completed consultation is required to purchase this product."
              }, status: :unprocessable_entity and return
            end

            super
          end

          def remove_line_item
            spree_authorize! :update, spree_current_order, order_token
            
            line_item.destroy
            spree_current_order.recalculate
            
            render_serialized_payload { serialized_current_order }
          end

          private

          # Override to accept :id parameter instead of :line_item_id
          def line_item
            @line_item ||= spree_current_order.line_items.find(params[:id] || params[:line_item_id])
          end
        end
      end
    end
  end
end

if defined?(Spree::Api::V2::Storefront::CartController)
  Spree::Api::V2::Storefront::CartController.class_eval do
    prepend Spree::Api::V2::Storefront::CartControllerDecorator
  end
end