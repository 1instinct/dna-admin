module Spree
  class StoreController <  Spree::BaseController
    before_action :redirect_to_admin
    # skip_before_action :require_login
    
    def redirect_to_admin
      redirect_to admin_url
    end
  end
end