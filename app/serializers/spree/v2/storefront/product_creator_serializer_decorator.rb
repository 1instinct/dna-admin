# Marketplace attributes on the storefront product JSON:
#   digital_kind: the kind of the product's live digital asset, or null
#   creator:      { handle, name } of the creator who sells it, or null for store products
# Loaded by the to_prepare decorator glob; redefining a jsonapi-serializer attribute replaces it by
# name, so loading this more than once is harmless.
module Spree
  module V2
    module Storefront
      module ProductCreatorSerializerDecorator
        def self.apply(serializer)
          serializer.attribute(:digital_kind) do |product|
            Spree::DigitalAsset.published.where(variant_id: product.variants_including_master.map(&:id))
                               .order(version: :desc, id: :desc).pick(:kind)
          end
          serializer.attribute(:creator) { |product| Creators.identity(product) }
        end
      end
    end
  end
end

Spree::V2::Storefront::ProductCreatorSerializerDecorator.apply(Spree::V2::Storefront::ProductSerializer)
