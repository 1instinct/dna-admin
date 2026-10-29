module Spree
  module Api
    module V1
      # Authenticates the app's user from an OAuth Bearer token (Spree's
      # Doorkeeper password grant) or the X-Spree-Token API key header, and
      # renders JSON errors. Replaces the base controller's API-key-only
      # before_actions (which render RABL templates) for JSON-only endpoints.
      module UserAuthentication
        extend ActiveSupport::Concern

        included do
          skip_before_action :load_user, :authorize_for_order, :authenticate_user, :load_user_roles, raise: false
          rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
        end

        private

        def api_user
          return @api_user if defined?(@api_user)

          @api_user = user_from_bearer || user_from_api_key
        end

        def require_api_user!
          render_error('unauthorized', :unauthorized, 'A valid Bearer token or X-Spree-Token is required') unless api_user
        end

        def user_from_bearer
          header = request.authorization.to_s
          return nil unless header.start_with?('Bearer ')

          token = Doorkeeper::AccessToken.by_token(header.split(' ', 2).last.to_s.strip)
          return nil unless token&.accessible?

          Spree.user_class.find_by(id: token.resource_owner_id)
        end

        def user_from_api_key
          key = request.headers['X-Spree-Token'].to_s
          return nil if key.blank?

          Spree.user_class.find_by(spree_api_key: key)
        end

        def render_error(code, status, message = nil)
          render json: { error: code.to_s, message: message || code.to_s.humanize }, status: status
        end

        def render_not_found
          render_error('not_found', :not_found)
        end
      end
    end
  end
end
