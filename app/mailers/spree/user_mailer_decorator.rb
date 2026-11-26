module Spree
  # The reset-password link opens this app's own reset page (/user/spree_user/password/edit),
  # so it has to point at the admin, not at the store's URL, which is the
  # storefront domain. ADMIN_URL (e.g. https://admin.example.com) says where the
  # admin lives; unset, the link keeps Spree's default of the store URL.
  #
  # It is read from configuration, never from the request: the Host header is
  # client-controlled and would let anyone point a victim's reset link elsewhere.
  module UserMailerDecorator
    def reset_password_instructions(user, token, *args)
      admin_url = ENV['ADMIN_URL'].presence
      return super unless admin_url

      current_store_id = args.inject({}, :merge)[:current_store_id]
      @current_store = Spree::Store.find_by(id: current_store_id) || Spree::Store.default
      @locale = @current_store.has_attribute?(:default_locale) ? @current_store.default_locale : I18n.default_locale
      I18n.locale = @locale if @locale.present?
      @edit_password_reset_url = spree.edit_spree_user_password_url(reset_password_token: token, host: admin_url)
      @user = user

      mail to: user.email, from: from_address,
           subject: "#{@current_store.name} #{I18n.t(:subject, scope: %i[devise mailer reset_password_instructions])}",
           store_url: @current_store.url
    end
  end
end

Spree::UserMailer.prepend(Spree::UserMailerDecorator)
