module Spree
  module V2
    module Storefront
      # Storefront JSON for Spree::ProductVideo (type "product_video"), via
      # GET /api/v2/storefront/products?include=videos. All urls are paths, like image styles.
      class ProductVideoSerializer < BaseSerializer
        set_type :product_video

        attributes :alt, :position

        attribute(:url) { |video| video.video_url }
        attribute(:content_type) { |video| video.video_content_type }
        attribute(:byte_size) { |video| video.video_byte_size }
        attribute(:poster_url) { |video| video.poster_url }
        attribute(:poster_thumb_url) { |video| video.poster_thumb_url }
      end
    end
  end
end
