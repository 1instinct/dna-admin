# Extra storefront image attributes. `styles` is left exactly as it was: for a GIF those
# variants are still first frames and act as the poster; `animated_url` is the original.
# The name is deliberately not `original_url`, which shipped clients already read.
#
# Loaded by the to_prepare decorator glob; redefining a jsonapi-serializer attribute replaces
# it by name, so loading this more than once is harmless.
module Spree
  module V2
    module Storefront
      module ImageSerializerDecorator
        def self.apply(serializer)
          serializer.class_eval do
            attributes :alt, :position

            attribute(:content_type) { |image| image.media_content_type }
            attribute(:width) { |image| image.media_width }
            attribute(:height) { |image| image.media_height }
            attribute(:byte_size) { |image| image.media_byte_size }
            attribute(:animated) { |image| image.animated? }
            attribute(:animated_url) { |image| image.animated_url }
          end
        end
      end
    end
  end
end

Spree::V2::Storefront::ImageSerializerDecorator.apply(Spree::V2::Storefront::ImageSerializer)
