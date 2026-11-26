module DigitalAssets
  # Free products: a variant can be claimed (ownership source "free") when its product is on sale,
  # its price is 0, its product property DigitalAssets.config.claimable_property is "true", and it
  # has a published asset.
  module Claim
    module_function

    def claimable?(variant)
      return false unless variant && !variant.deleted? && !variant.discontinued?

      product = variant.product
      return false unless product&.available?
      return false unless variant.price.present? && variant.price.to_d.zero?
      return false unless product.property(DigitalAssets.config.claimable_property).to_s.strip.casecmp?('true')

      variant.digital?
    end
  end
end
