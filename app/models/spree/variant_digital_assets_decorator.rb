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

    def digital?
      digital_assets.published.exists?
    end

    # A digital variant has no stock: it can always be supplied and never moves inventory.
    def should_track_inventory?
      return false if digital?

      super
    end
  end
end

Spree::Variant.prepend(Spree::VariantDigitalAssetsDecorator) unless Spree::Variant.include?(Spree::VariantDigitalAssetsDecorator)
