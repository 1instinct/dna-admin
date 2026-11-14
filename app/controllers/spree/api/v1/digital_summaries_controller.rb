module Spree
  module Api
    module V1
      # What a digital product contains, for its public product page. No auth.
      #
      #   GET /api/v1/products/:slug/digital_summary
      #       200 { product_id, slug, kind, version, file_count, byte_size, sample_count,
      #             files: [{ filename, byte_size, content_type }], creator: { handle, name } | null }
      #       404 unless the product is on sale and has a published asset
      #
      # Describes the live (highest published) version. sample_count is the length of the
      # manifest's "samples" list, or null when it has none. No download links.
      class DigitalSummariesController < Spree::Api::BaseController
        include Profiles::ApiResponses

        skip_before_action :authenticate_user

        def show
          product = Spree::Product.publicly_visible.find_by(slug: params[:slug].to_s)
          asset = product && live_asset(product)
          return render_not_found unless asset

          samples = asset.manifest.is_a?(Hash) ? asset.manifest['samples'] : nil
          files = asset.file_entries
          render json: {
            product_id: product.id,
            slug: product.slug,
            kind: asset.kind,
            version: asset.version,
            file_count: files.size,
            byte_size: asset.byte_size,
            sample_count: samples.is_a?(Array) ? samples.size : nil,
            files: files.map { |file| file.slice(:filename, :byte_size, :content_type) },
            creator: Creators.identity(product)
          }
        end

        private

        def live_asset(product)
          Spree::DigitalAsset.published.where(variant_id: product.variants_including_master.select(:id))
                             .order(version: :desc, id: :desc).first
        end
      end
    end
  end
end
