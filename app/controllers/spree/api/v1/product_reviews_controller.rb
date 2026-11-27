module Spree
  module Api
    module V1
      # Public product reviews. Contract: docs/plans/2026-11-26-reviews-api-contract.md.
      #
      #   GET /api/v1/products/:product_id/review_summary?scope=
      #   GET /api/v1/products/:product_id/reviews?scope=&sort=&rating[]=&with_photos=1&written=1&page=&per_page=
      #
      # :product_id is a slug or an id; products the public can't see are 404. scope is retail
      # (default), all or wholesale; the last two need a Bearer token for a wholesale or admin
      # user (403 otherwise). The storefront's shared X-Spree-Token key never counts as that
      # user, whoever owns it. An invalid Bearer token is 401.
      class ProductReviewsController < Spree::Api::BaseController
        include Profiles::ApiResponses
        include Swagger::Blocks

        SORTS = {
          'helpful' => 'helpful_count DESC, published_at DESC, id DESC',
          'recent' => 'published_at DESC, id DESC',
          'rating_desc' => 'rating DESC, published_at DESC, id DESC',
          'rating_asc' => 'rating ASC, published_at DESC, id DESC'
        }.freeze
        PER_PAGE_DEFAULT = 10
        PER_PAGE_MAX = 50

        skip_before_action :authenticate_user
        before_action :reject_bad_bearer
        before_action :load_product
        before_action :load_scope

        def summary
          render json: presenter.summary(@product, @scope)
        end

        def index
          reviews = Spree::Review.published.where(reviewable: @product).in_scope(@scope)
          reviews = reviews.where(rating: ratings) if ratings.any?
          reviews = reviews.where(id: photo_review_ids) if truthy?(params[:with_photos])
          reviews = reviews.written if truthy?(params[:written])
          page = reviews.order(Arel.sql(SORTS.fetch(params[:sort].to_s, SORTS['helpful']))).
                 includes(variant: { option_values: :option_type }, photos_attachments: :blob).
                 page(page_number).per(per_page)

          render json: {
            data: page.map { |review| presenter.review(review) },
            meta: { page: page.current_page, per_page: page.limit_value, total_count: page.total_count,
                    total_pages: page.total_pages, scope: @scope }
          }
        end

        private

        # A Bearer token that doesn't resolve to an active user is refused rather than ignored.
        def reject_bad_bearer
          render_error('unauthorized', :unauthorized) if bearer_token.present? && current_api_user.nil?
        end

        # Only a Bearer user can unlock wholesale reviews; api-key requests are anonymous here.
        def review_viewer
          bearer_token.present? ? current_api_user : nil
        end

        def load_product
          scope = Spree::Product.publicly_visible
          id = params[:product_id].to_s
          @product = scope.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          @product = id.match?(/\A\d+\z/) ? scope.find_by(id: id) : nil
          render_not_found unless @product
        end

        def load_scope
          @scope = Reviews::Channel.allowed_scope(params[:scope].presence || 'retail', review_viewer)
        rescue Reviews::Error => e
          render_error(e.message, :forbidden)
        end

        def presenter
          @presenter ||= Reviews::Presenter.new(base_url: Reviews.asset_base_url(request))
        end

        def ratings
          @ratings ||= Array(params[:rating]).map { |value| Integer(value, exception: false) }.compact.select { |n| n.between?(1, 5) }.uniq
        end

        def photo_review_ids
          ActiveStorage::Attachment.where(record_type: Spree::Review.name, name: 'photos').select(:record_id)
        end

        def page_number
          [params[:page].to_i, 1].max
        end

        def per_page
          value = params[:per_page].to_i
          value.positive? ? [value, PER_PAGE_MAX].min : PER_PAGE_DEFAULT
        end

        def truthy?(value)
          ActiveModel::Type::Boolean.new.cast(value) == true
        end

        swagger_path '/products/{product_id}/review_summary' do
          operation :get do
            key :summary, 'Rating summary for a product'
            key :description, 'Average, histogram, attribute averages, AI summary and latest photos. scope=all|wholesale needs a wholesale or admin Bearer token.'
            key :tags, ['Reviews']
            parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
            parameter name: :scope, in: :query, required: false, type: :string, enum: %w[retail all wholesale]
            response(200) { key :description, 'Summary' }
            response(403) { key :description, 'Wholesale scope without a wholesale account' }
            response(404) { key :description, 'Unknown or hidden product' }
          end
        end

        swagger_path '/products/{product_id}/reviews' do
          operation :get do
            key :summary, 'Published reviews for a product'
            key :description, 'Paginated. Default sort is most helpful. scope=all|wholesale needs a wholesale or admin Bearer token.'
            key :tags, ['Reviews']
            parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
            parameter name: :scope, in: :query, required: false, type: :string, enum: %w[retail all wholesale]
            parameter name: :sort, in: :query, required: false, type: :string, enum: SORTS.keys
            parameter name: 'rating[]', in: :query, required: false, type: :array, items: { type: :integer },
                      collectionFormat: :multi
            parameter name: :with_photos, in: :query, required: false, type: :boolean
            parameter name: :written, in: :query, required: false, type: :boolean
            parameter name: :page, in: :query, required: false, type: :integer
            parameter name: :per_page, in: :query, required: false, type: :integer
            response(200) { key :description, '{ data: [review], meta: { page, per_page, total_count, total_pages, scope } }' }
            response(403) { key :description, 'Wholesale scope without a wholesale account' }
            response(404) { key :description, 'Unknown or hidden product' }
          end
        end
      end
    end
  end
end
