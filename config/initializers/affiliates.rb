# Affiliate program (app/services/affiliates.rb holds Affiliates.config).
#
# Defaults: commission 1000 bps (10%), cookie 30 days, 30-day hold before a commission is approved.
#
# ENV:
#   AFFILIATE_LINK_BASE_URL  storefront base for affiliate links (falls back to SITE_URL)
#   AFFILIATE_VISITOR_SALT   salt for click visitor hashes (derived from secret_key_base when unset)
#
# Pending commissions become approved lazily on the affiliate endpoints and with
# `rake affiliates:sweep` (run it daily from a scheduler).
Rails.application.config.to_prepare do
  Spree::User.include(Affiliates::UserExtension) unless Spree::User.include?(Affiliates::UserExtension)
end
