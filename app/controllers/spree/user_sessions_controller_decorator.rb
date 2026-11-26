module Spree
  # With no page to return to, send an admin to the admin, not the storefront
  # account page Spree defaults to.
  module UserSessionsControllerDecorator
    private

    def after_sign_in_redirect(resource_or_scope)
      stored_location_for(resource_or_scope) ||
        (spree_current_user&.has_spree_role?('admin') ? spree.admin_path : super)
    end
  end
end

Spree::UserSessionsController.prepend(Spree::UserSessionsControllerDecorator)
