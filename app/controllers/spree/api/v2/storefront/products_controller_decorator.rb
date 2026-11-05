module Spree
  module Api
    module V2
      module Storefront
        module ProductsControllerDecorator
          VIDEO_INCLUDES = { videos: { video_attachment: :blob, poster_attachment: :blob } }.freeze

          private

          # Preloads product videos and their attachments when a request asks for include=videos,
          # so a listing doesn't query per product and per video.
          def scope_includes
            return super unless params[:include].to_s.split(',').map(&:strip).include?('videos')

            super.merge(VIDEO_INCLUDES)
          end

          # Both show and index start here, so a product that isn't available is a 404 by slug and
          # by id, and no filter can list it. Admins keep the whole catalog.
          def scope
            catalog_admin? ? super : super.publicly_visible
          end

          # Spree's finder reads these two from the query string. show_deleted lifts the deleted
          # condition of the scope above, and show_discontinued skips Spree's own `available`.
          def collection
            drop_catalog_admin_filters unless catalog_admin?
            super
          end

          def drop_catalog_admin_filters
            filter = params[:filter]
            return unless filter.is_a?(ActionController::Parameters)

            filter.delete(:show_deleted)
            filter.delete(:show_discontinued)
          end

          def catalog_admin?
            spree_current_user&.has_spree_role?('admin')
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
