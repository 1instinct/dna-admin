# Digital products and ownership (app/services/digital_assets.rb holds DigitalAssets.config).
#
# An app restricts the asset kinds and validates each kind's manifest in its own initializer:
#
#   Rails.application.config.to_prepare do
#     DigitalAssets.configure do |c|
#       c.kinds = %w[pack preset]
#       c.manifest_validators['pack'] = ->(manifest, asset) { [] } # array of error strings
#     end
#   end
#
# The manifest key "files" is written by the server (sha256 per file, DigitalAssets::ChecksumJob);
# an app's schema should not use it for anything else.
Rails.application.config.to_prepare do
  DigitalAssets.configure do |c|
    c.revoked_visibility_days = 7
    c.link_ttl = 10.minutes
  end
end
