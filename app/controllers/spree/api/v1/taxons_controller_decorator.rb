# Spree's v1 taxons#products lists a taxon's products with no regard for their state. The admin's
# taxon drag-sort needs every product, so admins keep that; anyone else gets available ones only.
module Spree
  module Api
    module V1
      module TaxonsControllerDecorator
        def products
          return super if catalog_admin?

          taxon = Spree::Taxon.find(params[:id])
          @products = taxon.products.publicly_visible.ransack(params[:q]).result
          @products = @products.page(params[:page]).per(params[:per_page] || 500)
          render 'spree/api/v1/products/index'
        end
      end
    end
  end
end

# Referenced directly so the classic autoloader loads the controller: a `defined?` guard is nil
# for a constant that hasn't been autoloaded yet, and the decorator would silently not apply.
unless Spree::Api::V1::TaxonsController < Spree::Api::V1::TaxonsControllerDecorator
  Spree::Api::V1::TaxonsController.prepend(Spree::Api::V1::TaxonsControllerDecorator)
end
