# The shared email frame (layouts/store_mailer and layouts/spree/base_mailer): store logo,
# patterned background, copyright footer. Everything here returns absolute URLs or nil, because
# email can't use paths; nil means "leave it out".
module StoreMailerHelper
  BACKGROUNDS = { light: '/email/pattern-light.png', dark: '/email/pattern-dark.png' }.freeze

  def mailer_store
    @mailer_store ||= @order&.store || @store || Spree::Store.default
  end

  def mailer_store_name
    mailer_store&.name.to_s.strip.presence || 'Our store'
  end

  # This app's public address (ADMIN_URL, see config/initializers/mailer_host.rb), or nil.
  def mailer_base_url
    options = (Rails.application.routes.default_url_options || {}).symbolize_keys
    return if options[:host].blank?

    port = options[:port].present? ? ":#{options[:port]}" : ''
    "#{options[:protocol].presence || 'https'}://#{options[:host]}#{port}".sub('://://', '://')
  end

  def mailer_asset_url(path)
    base = mailer_base_url
    base && "#{base}#{path}"
  end

  def mailer_background_url(scheme = :light)
    mailer_asset_url(BACKGROUNDS.fetch(scheme))
  end

  # The store's email logo (Stores > store > Mailer logo), else its logo, as an absolute URL.
  def mailer_logo_url
    return unless mailer_base_url && mailer_store

    logo = [mailer_store.mailer_logo, mailer_store.logo].find { |attachment| attachment.respond_to?(:attached?) && attachment.attached? }
    return unless logo

    target = logo.variable? ? logo.variant(resize: '480x160>') : logo
    Rails.application.routes.url_helpers.url_for(target)
  rescue StandardError
    nil
  end

  # The storefront (SITE_URL), where "Visit the store" goes.
  def mailer_site_url
    SITE_URL.to_s.strip.chomp('/').presence if defined?(SITE_URL)
  end

  def mailer_social_links
    { 'Instagram' => social_url(mailer_store&.instagram, 'https://instagram.com/'),
      'Facebook' => social_url(mailer_store&.facebook, 'https://facebook.com/'),
      'X' => social_url(mailer_store&.twitter, 'https://x.com/') }.compact
  end

  def mailer_copyright
    "© #{Time.current.year} #{mailer_store_name}. All rights reserved."
  end

  private

  def social_url(value, prefix)
    handle = value.to_s.strip
    return if handle.blank?
    return handle if handle.match?(%r{\Ahttps?://})

    "#{prefix}#{handle.delete_prefix('@')}"
  end
end
