module Spree
  module Api
    module V1
      module Creator
        # A creator's own digital products (see Creators::ProductJson for the product hash).
        #
        #   GET    /api/v1/creator/products             200 { products: [Product] }, newest first
        #   POST   /api/v1/creator/products             201 Product | 422 { error, fields }
        #   GET    /api/v1/creator/products/:id         200 Product | 404
        #   PATCH  /api/v1/creator/products/:id         200 Product | 404 | 422 (in review, rejected, invalid)
        #   DELETE /api/v1/creator/products/:id         204 | 404 | 422 unless a draft that never went live
        #   POST   /api/v1/creator/products/:id/submit  200 Product | 422 unless draft or changes_requested with files
        #
        # Create and update take { name, description, price, kind, taxon_ids, preview_image_signed_id,
        # preview_audio_signed_id, files: [signed_id], keep_file_ids: [id], remove_file_ids: [id], manifest }; see
        # Creators::ProductWriter. Another creator's product, or a store product, is a 404.
        class ProductsController < Spree::Api::V1::Creator::BaseController
          WRITABLE = %i[name description price kind taxon_ids preview_image_signed_id preview_audio_signed_id files
                        keep_file_ids remove_file_ids manifest].freeze

          before_action :load_product, except: %i[index create]

          def index
            products = own_products.order(created_at: :desc, id: :desc).includes(master: :images)
            render json: { products: products.map { |product| product_json(product) } }
          end

          def show
            render json: product_json(@product)
          end

          def create
            product = Creators::ProductWriter.create(current_api_user, writable_attributes)
            render json: product_json(product.reload), status: :created
          rescue Creators::ProductWriter::Invalid => e
            render_error(e.message, :unprocessable_entity, fields: e.fields)
          end

          def update
            product = Creators::ProductWriter.update(@product, writable_attributes)
            render json: product_json(product.reload)
          rescue Creators::ProductWriter::Invalid => e
            render_error(e.message, :unprocessable_entity, fields: e.fields)
          end

          def destroy
            unless @product.review_state == 'draft' && @product.available_on.nil? && @product.master.live_digital_asset.nil?
              return render_error('Only a draft can be deleted', :unprocessable_entity)
            end

            @product.destroy!
            head :no_content
          end

          def submit
            unless %w[draft changes_requested].include?(@product.review_state)
              return render_error('Only a draft or a product with requested changes can be submitted', :unprocessable_entity)
            end

            draft = Spree::DigitalAsset.draft.where(variant_id: @product.master.id).order(id: :desc).first
            unless draft&.files&.attached?
              return render_error('Add files before submitting', :unprocessable_entity, fields: { files: ['are required'] })
            end

            @product.update!(review_state: 'submitted', submitted_at: Time.current, review_note: nil)
            render json: product_json(@product)
          end

          private

          def own_products
            Spree::Product.where(creator_id: current_api_user.id)
          end

          def load_product
            @product = own_products.find_by(id: params[:id])
            render_not_found unless @product
          end

          def writable_attributes
            WRITABLE.each_with_object({}) do |key, attrs|
              attrs[key] = plain(params[key]) if params.key?(key)
            end
          end

          def product_json(product)
            Creators::ProductJson.call(product, base_url: request.base_url)
          end
        end
      end
    end
  end
end
