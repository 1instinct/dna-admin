# Marketplace attributes on the storefront product JSON:
#   digital_kind: the kind of the product's live digital asset, or null
#   creator:      { handle, name } of the creator who sells it, or null for store products
# A listing preloads the assets (Spree::Api::V2::Storefront::ProductsControllerDecorator) and passes
# the creators' identities in params[:creator_identities], so neither queries per product.
# Loaded by the to_prepare decorator glob; redefining a jsonapi-serializer attribute replaces it by
# name, so loading this more than once is harmless.
module Spree
  module V2
    module Storefront
      module ProductCreatorSerializerDecorator
        def self.apply(serializer)
          serializer.attribute(:digital_kind) { |product| Creators.digital_kind(product) }
          serializer.attribute(:creator) do |product, params|
            identities = params && params[:creator_identities]
            identities ? identities[product.creator_id] : Creators.identity(product)
          end
        end
      end
    end
  end
end

Spree::V2::Storefront::ProductCreatorSerializerDecorator.apply(Spree::V2::Storefront::ProductSerializer)
