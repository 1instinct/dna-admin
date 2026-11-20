module Spree
  module Api
    module V1
      # DELETE /api/v1/account: the signed-in user deletes their own account.
      #
      # Requires an OAuth bearer token (Authorization: Bearer). 204 when deleted; 401 when the
      # token is missing, invalid, expired or revoked (so a repeat call after success is 401);
      # 422 { "error": "<message>" } when deletion is refused for a stated reason.
      class AccountController < Spree::Api::BaseController
        before_action :require_bearer_user

        def destroy
          AccountDeletion.call(current_api_user)
          head :no_content
        rescue AccountDeletion::Refused => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::ActiveRecordError => e
          Rails.logger.error("[account_deletion] user_id=#{current_api_user.id} failed: #{e.class}")
          render json: { error: 'Account deletion failed. Try again later.' }, status: :internal_server_error
        end

        private

        # The base controller already 401s an invalid bearer; this also turns away api-key-only
        # and anonymous requests.
        def require_bearer_user
          return if bearer_token.present? && current_api_user&.persisted?

          render json: { error: 'unauthorized' }, status: :unauthorized
        end
      end
    end
  end
end
