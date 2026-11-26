# Adds to the storefront product JSON:
#   - the `videos` relationship (type "product_video"), requested with include=videos
#   - the review ratings: avg_rating and reviews_count (retail, what the public sees) and
#     all_avg_rating and all_reviews_count (every channel, for wholesale pages). Counts include
#     star-only ratings. Reviews::RefreshStats keeps the columns current.
# Re-declaring a jsonapi-serializer attribute or relationship replaces it by name, so loading this
# more than once is harmless.
module Spree
  module V2
    module Storefront
      module ProductSerializerDecorator
        RATING_ATTRIBUTES = %i[avg_rating reviews_count all_avg_rating all_reviews_count].freeze

        def self.apply(serializer)
          serializer.has_many :videos, record_type: :product_video, serializer: :product_video
          serializer.attributes(*RATING_ATTRIBUTES)
        end
      end
    end
  end
end

Spree::V2::Storefront::ProductSerializerDecorator.apply(Spree::V2::Storefront::ProductSerializer)
