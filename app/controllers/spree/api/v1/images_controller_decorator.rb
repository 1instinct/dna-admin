# Spree's v1 images find their product or variant with no regard for its state. Anyone but an
# admin now gets a 404 for an unavailable product.
module Spree
  module Api
    module V1
      module ImagesControllerDecorator
        private

        def scope
          record = super
          return record if catalog_admin?

          product = record.is_a?(Spree::Variant) ? record.product : record
          raise ActiveRecord::RecordNotFound unless product&.available?

          record
        end
      end
    end
  end
end

# Referenced directly so the classic autoloader loads the controller: a `defined?` guard is nil
# for a constant that hasn't been autoloaded yet, and the decorator would silently not apply.
unless Spree::Api::V1::ImagesController < Spree::Api::V1::ImagesControllerDecorator
  Spree::Api::V1::ImagesController.prepend(Spree::Api::V1::ImagesControllerDecorator)
end
