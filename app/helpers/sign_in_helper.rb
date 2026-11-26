# Branding for the signed-out screens (layout spree/layouts/sign_in).
module SignInHelper
  DEFAULT_LOGO = 'instinct_logo.png'.freeze
  DEFAULT_BACKGROUND = 'background.jpg'.freeze
  # A 1280px copy of the default background for phones (80 KB instead of 165 KB).
  DEFAULT_MOBILE_BACKGROUND = 'background-mobile.jpg'.freeze

  def sign_in_logo_path
    sign_in_asset_path(ENV['COMPANY_LOGO'], DEFAULT_LOGO)
  end

  def sign_in_background_path
    sign_in_asset_path(ENV['COMPANY_BACKGROUND'], DEFAULT_BACKGROUND)
  end

  # COMPANY_BACKGROUND_MOBILE names a smaller copy of COMPANY_BACKGROUND for phones. Unset, the
  # default background uses its own small copy and any other background is used as is.
  def sign_in_mobile_background_path
    background = sign_in_asset_name(ENV['COMPANY_BACKGROUND'], DEFAULT_BACKGROUND)
    mobile = ENV['COMPANY_BACKGROUND_MOBILE'].presence
    mobile ||= DEFAULT_MOBILE_BACKGROUND if background == DEFAULT_BACKGROUND
    mobile ? sign_in_asset_path(mobile, background) : sign_in_background_path
  end

  private

  # COMPANY_LOGO / COMPANY_BACKGROUND are set as a logical asset name ("instinct_logo.png"), a
  # URL, or a path such as "/assets/instinct_logo.png". That last form is passed through
  # untouched by asset_path and misses the fingerprinted file, so it is read as the logical name.
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

    asset_path(sign_in_asset_name(fallback, fallback))
  end
end
