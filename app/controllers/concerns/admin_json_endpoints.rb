# JSON endpoints in the Rails admin (menus, inbox, visitors): the admin's session and CSRF token
# (the pages send X-CSRF-Token from csrf_meta_tags), errors as { error: { code, message } }, and
# a 401 or 403 instead of Spree's redirect to the login or forbidden page, which fetch would
# otherwise follow and read as HTML.
module AdminJsonEndpoints
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do |e|
      raise e unless json_request?

      render_json_error('not_found', 'Not found.', :not_found)
    end
  end

  private

  def json_request?
    request.format.json? || request.content_mime_type&.json?
  end

  def render_json_error(code, message, status = :unprocessable_entity)
    render json: { error: { code: code, message: message } }, status: status
  end

  def redirect_unauthorized_access
    return super unless json_request?

    if try_spree_current_user
      render_json_error('forbidden', Spree.t(:authorization_failure), :forbidden)
    else
      render_json_error('authentication_required', 'Sign in to the admin.', :unauthorized)
    end
  end
end
