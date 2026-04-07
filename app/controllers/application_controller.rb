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
  
  def logged_in?
    spree_current_user != nil
  end

  def require_login
    unless logged_in?
      flash[:error] = "Please Login or Sign Up"
      # render('spree/no_auth')
      render :partial => 'spree/shared/login'
      # redirect_to spree_login_path
    end
  end
end
