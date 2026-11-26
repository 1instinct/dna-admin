# Branding for the signed-out screens (layout spree/layouts/sign_in).
module SignInHelper
  DEFAULT_LOGO = 'beeper_logo.png'.freeze
  DEFAULT_BACKGROUND = 'beeper-login-background.jpg'.freeze
  # 1280px, ~40 KB: what a phone gets instead of the 3200px, 1.9 MB original.
  MOBILE_BACKGROUNDS = { DEFAULT_BACKGROUND => 'beeper-login-background-mobile.jpg' }.freeze

  def sign_in_logo_path
    sign_in_asset_path(ENV['COMPANY_LOGO'], DEFAULT_LOGO)
  end

  def sign_in_background_path
    sign_in_asset_path(ENV['COMPANY_BACKGROUND'], DEFAULT_BACKGROUND)
  end

  def sign_in_mobile_background_path
    name = sign_in_asset_name(ENV['COMPANY_BACKGROUND'], DEFAULT_BACKGROUND)
    sign_in_asset_path(MOBILE_BACKGROUNDS.fetch(name, name), DEFAULT_BACKGROUND)
  end

  private

  # COMPANY_LOGO / COMPANY_BACKGROUND are set as a logical asset name
  # ("beeper_logo.png"), a URL, or (HEROKU_DEPLOYMENT.md) "/assets/beeper_logo.png".
  # That last form is passed through untouched by asset_path and misses the
  # fingerprinted file, so it is read as the logical name.
  def sign_in_asset_name(value, fallback)
    name = value.to_s.strip.presence || fallback
    name.match?(%r{\A(https?:)?//}) ? name : name.delete_prefix('/assets/')
  end

  def sign_in_asset_path(value, fallback)
    name = sign_in_asset_name(value, fallback)
    return name if name.match?(%r{\A(https?:)?//})

    asset_path(name)
  rescue StandardError => e
    raise unless e.class.name.end_with?('AssetNotFound')

    asset_path(fallback)
  end
end
