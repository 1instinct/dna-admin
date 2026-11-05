# Spree's v1 variants answer for any variant whatever its product's state, nested under a product
# or not. Anyone but an admin now gets a 404 for an unavailable product and doesn't see its
# variants listed.
module Spree
  module Api
    module V1
      module VariantsControllerDecorator
        private

        def product
          super
          raise ActiveRecord::RecordNotFound if @product && !catalog_admin? && !@product.available?

          @product
        end

        def scope
          catalog_admin? ? super : super.joins(:product).merge(Spree::Product.publicly_visible)
        end
      end
    end
  end
end

# Referenced directly so the classic autoloader loads the controller: a `defined?` guard is nil
# for a constant that hasn't been autoloaded yet, and the decorator would silently not apply.
unless Spree::Api::V1::VariantsController < Spree::Api::V1::VariantsControllerDecorator
  Spree::Api::V1::VariantsController.prepend(Spree::Api::V1::VariantsControllerDecorator)
end
