module Spree
  module Api
    module V1
      module Iap
        # GET /api/v1/iap/account_token  the caller's stable UUID, to pass as
        # StoreKit appAccountToken / Play obfuscatedAccountId when purchasing.
        class AccountTokensController < Spree::Api::BaseController
          include Spree::Api::V1::UserAuthentication

          before_action :require_api_user!

          def show
            render json: { account_token: Spree::IapAccountToken.for(api_user).token }
          end
        end
      end
    end
  end
end
