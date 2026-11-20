module Spree
  module Api
    module V1
      module Iap
        # GET /api/v1/iap/entitlements   the caller's entitlements (e.g. pro)
        class EntitlementsController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication
          include Spree::Api::V1::IapJson

          before_action :require_api_user!

          def index
            render json: { entitlements: entitlements_json(api_user) }
          end
        end
      end
    end
  end
end
