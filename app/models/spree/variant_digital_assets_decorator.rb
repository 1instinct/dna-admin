# A variant's digital assets. The live asset is the highest published version. No dependent:
# variants are soft-deleted, and owners keep their files when a product is retired.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module VariantDigitalAssetsDecorator
    def self.prepended(base)
      base.has_many :digital_assets, class_name: 'Spree::DigitalAsset', foreign_key: :variant_id,
                                     inverse_of: :variant
      base.has_many :digital_ownerships, class_name: 'Spree::DigitalOwnership', foreign_key: :variant_id,
                                         inverse_of: :variant
    end

    def live_digital_asset
      digital_assets.published.order(version: :desc).first
    end

    # Whether the variant has a published asset. Uses the loaded digital_assets when preloaded;
    # otherwise one query, memoized on this instance (cart, checkout and stock checks ask often).
    # reload and DigitalAsset saves on this instance clear it.
    def digital?
      return digital_assets.any?(&:published?) if association(:digital_assets).loaded?
      return @digital if defined?(@digital)

      @digital = digital_assets.published.exists?
    end

    def reset_digital_cache!
      remove_instance_variable(:@digital) if defined?(@digital)
      association(:digital_assets).reset
    end

    def reload(*)
      reset_digital_cache!
      super
    end

    # A digital variant has no stock: it can always be supplied and never moves inventory.
    def should_track_inventory?
      return false if digital?

      super
    end

    # Spree 4.2 defines the track_inventory reader as should_track_inventory?, which would show
    # (and the admin form would save) false for every digital variant. Keep the reader on the
    # column and the global setting only.
    def track_inventory
      track_inventory? && Spree::Config.track_inventory_levels
    end
  end
end

Spree::Variant.prepend(Spree::VariantDigitalAssetsDecorator) unless Spree::Variant.include?(Spree::VariantDigitalAssetsDecorator)
