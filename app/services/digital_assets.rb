# Digital products: versioned file sets on variants (Spree::DigitalAsset) and who owns them
# (Spree::DigitalOwnership). Settings live on DigitalAssets.config; an app sets its own in an
# initializer (see config/initializers/digital_assets.rb).
module DigitalAssets
  class Config
    # kinds: allowed asset kinds; empty allows any kind.
    # manifest_validators: { kind => callable(manifest[, asset]) returning an array of error strings }.
    # revoked_visibility_days: how long the library keeps listing a revoked item.
    # link_ttl: lifetime of a signed download link.
    # links_rate_limit: per-user limit on POST /api/v1/library/:id/links.
    # max_asset_bytes: total size of one asset's files.
    # claimable_property: product property that makes a price-0 product claimable when "true".
    attr_accessor :kinds, :manifest_validators, :revoked_visibility_days, :link_ttl, :links_rate_limit,
                  :max_asset_bytes, :claimable_property

    def initialize
      @kinds = []
      @manifest_validators = {}
      @revoked_visibility_days = 7
      @link_ttl = 10.minutes
      @links_rate_limit = { limit: 60, window: 1.minute }
      @max_asset_bytes = 1.gigabyte
      @claimable_property = 'claimable'
    end
  end

  def self.config
    @config ||= Config.new
  end

  # Apps call this from a to_prepare block. The block is kept so reset_config! can replay it.
  def self.configure(&block)
    configurers << block
    block.call(config)
  end

  # Tests use this to drop settings they changed: back to the defaults plus the app's configure blocks.
  def self.reset_config!
    @config = nil
    configurers.each { |block| block.call(config) }
  end

  def self.configurers
    @configurers ||= []
  end
end
