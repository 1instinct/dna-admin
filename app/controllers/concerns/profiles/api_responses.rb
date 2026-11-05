module Profiles
  # Shared bits for the profile, block and report v1 endpoints: plain JSON errors
  # `{ "error": "message", "fields": { ... } }` and bearer handling.
  module ApiResponses
    extend ActiveSupport::Concern

    included do
      rescue_from ActionController::ParameterMissing do |e|
        render_error("#{e.param} is required", :unprocessable_entity)
      end
    end

    private

    # Bearer (Authorization: Bearer) required; api-key-only and anonymous requests are 401.
    def require_bearer_user
      return if bearer_token.present? && current_api_user&.persisted?

      render_error('unauthorized', :unauthorized)
    end

    # A signed-in viewer, or nil for anonymous requests.
    def viewer
      current_api_user&.persisted? ? current_api_user : nil
    end

    def enforce_rate_limit(action)
      return if Profiles::RateLimit.allow?(current_api_user, action)

      render_error('Too many requests. Try again later.', :too_many_requests)
    end

    def render_error(message, status, fields: nil)
      body = { error: message }
      body[:fields] = fields if fields
      render json: body, status: status
    end

    def render_record_errors(record, message = nil)
      render_error(message || record.errors.full_messages.first || 'is invalid', :unprocessable_entity,
                   fields: record.errors.to_hash)
    end

    def render_not_found
      render_error('not found', :not_found)
    end

    def presenter(profile, viewer: self.viewer)
      Profiles::Presenter.new(profile, viewer: viewer, base_url: request.base_url)
    end

    # A visible profile by handle, or nil when missing, hidden, deleted, locked, or when a block
    # exists either way with the viewer.
    def visible_profile(handle, viewer: self.viewer)
      profile = Spree::UserProfile.visible.find_by_handle(handle)
      return unless profile
      return if viewer && Spree::UserBlock.between?(viewer, profile.user)

      profile
    end
  end
end
