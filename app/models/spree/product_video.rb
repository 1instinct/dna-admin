# A video on a product, shown before images on the storefront. Self-contained: its own table,
# attachments and admin controller, so it does not depend on Spree::Asset/Spree::Image.
#
# The poster is uploaded, not generated: the server has no ffmpeg, and a grid card must never
# be blank.
module Spree
  class ProductVideo < Spree::Base
    VIDEO_TYPES = %w[video/mp4 video/webm].freeze
    POSTER_TYPES = %w[image/jpeg image/png image/webp].freeze
    MAX_VIDEO_SIZE = 50.megabytes
    MAX_POSTER_SIZE = 10.megabytes
    POSTER_SIZE = '1000x1000>'.freeze
    POSTER_THUMB_SIZE = '240x240>'.freeze

    self.table_name = 'spree_product_videos'

    belongs_to :product, class_name: 'Spree::Product', touch: true, inverse_of: :videos
    acts_as_list scope: :product_id

    has_one_attached :video
    has_one_attached :poster

    validates :product, presence: true
    validates :alt, length: { maximum: 255 }
    validate :check_video
    validate :check_poster

    # Blob redirect path of the video file.
    def video_url
      return unless video.attached?

      url_helpers.rails_blob_path(video, only_path: true)
    end

    # Poster scaled to fit within 1000px.
    def poster_url
      poster_variant_path(POSTER_SIZE)
    end

    # Poster scaled to fit within 240px, for grid cards.
    def poster_thumb_url
      poster_variant_path(POSTER_THUMB_SIZE)
    end

    def video_content_type
      video.attached? ? video.content_type : nil
    end

    def video_byte_size
      video.attached? ? video.byte_size : nil
    end

    private

    def url_helpers
      Rails.application.routes.url_helpers
    end

    def poster_variant_path(size)
      return unless poster.attached? && poster.variable?

      url_helpers.polymorphic_path(poster.variant(resize: size), only_path: true)
    end

    def check_video
      check_attachment(:video, VIDEO_TYPES, MAX_VIDEO_SIZE, 'must be an MP4 or WebM video')
    end

    def check_poster
      check_attachment(:poster, POSTER_TYPES, MAX_POSTER_SIZE, 'must be a JPEG, PNG or WebP image')
    end

    def check_attachment(name, types, max_size, type_message)
      file = public_send(name)
      unless file.attached?
        errors.add(name, :blank)
        return
      end

      errors.add(name, type_message) unless types.include?(file.content_type)
      return unless file.byte_size.to_i > max_size

      errors.add(name, "must be #{max_size / 1.megabyte} MB or smaller")
    end
  end
end
