module Spree
  module Api
    module V1
      module Iap
        # GET /api/v1/iap/products[?platform=apple|google]  active store product ids
        # (public: the app loads prices from the store with these ids).
        class ProductsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication

          def index
            products = Spree::IapProduct.active.order(:platform, :product_id)
            products = products.where(platform: params[:platform]) if params[:platform].present?
            render json: {
              products: products.map do |p|
                { platform: p.platform, product_id: p.product_id, kind: p.kind, entitlement: p.entitlement, name: p.name }
              end
            }
          end
        end
      end
    end
  end
end
