# Adds the `videos` relationship (type "product_video") to the storefront product JSON,
# requested with include=videos. Re-declaring a jsonapi-serializer relationship replaces it by
# name, so loading this more than once is harmless.
module Spree
  module V2
    module Storefront
      module ProductSerializerDecorator
        def self.apply(serializer)
          serializer.has_many :videos, record_type: :product_video, serializer: :product_video
        end
      end
    end
  end
end

Spree::V2::Storefront::ProductSerializerDecorator.apply(Spree::V2::Storefront::ProductSerializer)
