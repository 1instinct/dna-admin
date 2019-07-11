class ApplicationController < ActionController::Base
  def after_sign_in_path_for(resource)
    if spree_current_user.has_spree_role?("admin")
      admin_path
    # elsif spree_current_user.has_spree_role?("designer")
    #   '/designers/spree_variants/new' #rails helper gives the wrong path, not sure why
    else
      root_path
    end
  end
end
