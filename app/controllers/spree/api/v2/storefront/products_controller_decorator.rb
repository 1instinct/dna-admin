module Spree
  module Api
    module V2
      module Storefront
        # Preloads product videos and their attachments when a request asks for include=videos,
        # so a listing doesn't query per product and per video.
        module ProductsControllerDecorator
          VIDEO_INCLUDES = { videos: { video_attachment: :blob, poster_attachment: :blob } }.freeze

          private

          def scope_includes
            return super unless params[:include].to_s.split(',').map(&:strip).include?('videos')

            super.merge(VIDEO_INCLUDES)
          end
        end
      end
    end
  end
end

# Referenced directly so the classic autoloader loads the controller: a `defined?` guard is nil
# for a constant that hasn't been autoloaded yet, and the decorator would silently not apply.
unless Spree::Api::V2::Storefront::ProductsController < Spree::Api::V2::Storefront::ProductsControllerDecorator
  Spree::Api::V2::Storefront::ProductsController.prepend(Spree::Api::V2::Storefront::ProductsControllerDecorator)
end
