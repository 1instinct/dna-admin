class ApplicationController < ActionController::Base
  before_action :require_login
  # skip_before_action :require_login, only: [:spree_login]

  def after_sign_in_path_for(resource)
    if spree_current_user.has_spree_role?("admin")
      admin_path
    # elsif spree_current_user.has_spree_role?("designer")
    #   '/designers/spree_variants/new' #rails helper gives the wrong path, not sure why
    else
      root_path
    end
  end

  private

  # Devise controllers a signed-out visitor must be able to reach: the
  # "Forgot password?" link on the sign-in screen and the reset link in the
  # email. Without this the gate below swallowed them and showed the sign-in
  # form again.
  SIGNED_OUT_CONTROLLERS = %w[spree/user_passwords].freeze

  def logged_in?
    spree_current_user != nil
  end

  def require_login
    return if logged_in?
    return if SIGNED_OUT_CONTROLLERS.include?(controller_path)
    # An XHR/JSON call from an expired admin session gets a status, not an HTML page.
    return head(:unauthorized) if request.xhr? || request.format.json? || request.format.js?

    # Come back here after signing in. Without it Spree sent everyone to the
    # storefront's /account page, wherever they had been trying to go.
    if request.get? && !request.xhr? && !devise_controller?
      session['spree_user_return_to'] = request.fullpath
    end

    # A wrong email or password never reaches Devise's SessionsController#create
    # (its prepend_before_action authenticates first, and this gate renders when
    # that fails), so say what went wrong here.
    if request.post? && params[:spree_user].present?
      flash.now[:error] = I18n.t('devise.failure.invalid', authentication_keys: 'email')
    end

    # A full HTML page (doctype, viewport, title), not a bare partial: without
    # the viewport meta tag phones laid the old form out at desktop width.
    render template: 'spree/shared/sign_in', layout: 'spree/layouts/sign_in'
  end
end
