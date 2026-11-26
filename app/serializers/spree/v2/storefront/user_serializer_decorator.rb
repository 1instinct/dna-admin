# Adds `is_wholesale` to the storefront account JSON (GET /api/v2/storefront/account): true for
# users with the "wholesale" Spree role. dna-frontend switches to its wholesale pages on it.
# Same attribute name as the 1instinct Spree fork's own UserSerializer, which the app doesn't load
# (only the fork's `spree` meta-gem comes from GitHub; spree_api is the stock 4.2.5 gem).
# Re-declaring a jsonapi-serializer attribute replaces it by name, so loading this more than once
# is harmless.
module Spree
  module V2
    module Storefront
      module UserSerializerDecorator
        def self.apply(serializer)
          serializer.attribute(:is_wholesale) { |user| Reviews::Channel.wholesale_user?(user) }
        end
      end
    end
  end
end

Spree::V2::Storefront::UserSerializerDecorator.apply(Spree::V2::Storefront::UserSerializer)
