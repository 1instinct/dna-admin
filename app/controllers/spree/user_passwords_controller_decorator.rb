module Spree
  # Forgot/reset password pages share the mobile-first sign-in shell instead of
  # the storefront layout.
  module UserPasswordsControllerDecorator
    def self.prepended(base)
      base.layout 'spree/layouts/sign_in'
    end
  end
end

Spree::UserPasswordsController.prepend(Spree::UserPasswordsControllerDecorator)
