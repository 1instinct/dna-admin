# Media facts about a Spree::Image for the storefront API (see ImageSerializerDecorator).
# Kept apart from image_decorator.rb, which differs between apps and owns `styles`.
#
# Variants (`styles`) are always a single still frame, because Rails 6.1's image transformer
# loads page 0 only. For a GIF, `animated_url` is the untouched original, so clients can
# animate it while still using `styles` as the poster.
module Spree
  module ImageMediaDecorator
    ANIMATED_CONTENT_TYPES = %w[image/gif].freeze

    def media_content_type
      attachment.attached? ? attachment.content_type : nil
    end

    def media_byte_size
      attachment.attached? ? attachment.byte_size : nil
    end

    def media_width
      media_dimension('width')
    end

    def media_height
      media_dimension('height')
    end

    def animated?
      ANIMATED_CONTENT_TYPES.include?(media_content_type)
    end

    # Blob redirect path of the original file; nil unless the image is animated.
    def animated_url
      return unless animated?

      Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
    end

    private

    def media_dimension(key)
      return unless attachment.attached?

      value = attachment.blob.metadata[key]
      value.present? ? Integer(value) : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end

Spree::Image.prepend(Spree::ImageMediaDecorator) unless Spree::Image < Spree::ImageMediaDecorator
