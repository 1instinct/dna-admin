module Spree
  module Api
    module V1
      # The signed-in customer's reviews. Contract: docs/plans/2026-11-26-reviews-api-contract.md.
      #
      #   GET /api/v1/account/reviewables   products they've received, with their review if any
      #   GET /api/v1/account/reviews       their reviews, any status, newest first
      #   GET /api/v1/products/:product_id/review_form   what the composer needs for one product
      class AccountReviewsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        PER_PAGE_DEFAULT = 10
        PER_PAGE_MAX = 50

        skip_before_action :authenticate_user
        before_action :require_bearer_user

        def reviewables
          items = Reviews::Eligibility.for_user(current_api_user)
          render json: {
            data: items.map { |item| reviewable(item) },
            points: presenter.points_offer
          }
        end

        def index
          page = Spree::Review.for_products.where(user_id: current_api_user.id).newest_first.
                 includes(:reviewable, variant: { option_values: :option_type }, photos_attachments: :blob).
                 page([params[:page].to_i, 1].max).per(per_page)
          render json: {
            data: page.map { |review| presenter.own_review(review) },
            meta: { page: page.current_page, per_page: page.limit_value, total_count: page.total_count,
                    total_pages: page.total_pages }
          }
        end

        def form
          product = Spree::Product.publicly_visible.friendly.find(params[:product_id].to_s)
          reason = Reviews::Eligibility.reason_for(product, current_api_user)
          item = reason.nil? ? Reviews::Eligibility.item(product: product, user: current_api_user) : nil
          existing = Spree::Review.find_by(reviewable: product, user_id: current_api_user.id)
          render json: {
            eligible: reason.nil?,
            reason: reason,
            line_item_id: item&.line_item&.id,
            variant_label: item && variant_label(item.variant),
            existing_review: existing && presenter.own_review(existing),
            questions: Spree::ReviewAttribute.for_product(product).map { |attribute| presenter.question(attribute) },
            display_name: existing&.display_name || Spree::Review.default_display_name(order: item&.order, user: current_api_user),
            points: presenter.points_offer,
            limits: limits
          }
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        private

        def presenter
          @presenter ||= Reviews::Presenter.new(base_url: request.base_url)
        end

        def reviewable(item)
          product = item.product
          review = item.existing_review
          {
            line_item_id: item.line_item.id,
            order_number: item.order.number,
            product_id: product.id,
            slug: product.slug,
            name: product.name,
            image_url: presenter.product(product)[:image_url],
            variant_label: variant_label(item.variant),
            purchased_at: item.order.completed_at&.utc&.iso8601,
            existing_review: review && { id: review.id, rating: review.rating, status: review.status },
            questions: Spree::ReviewAttribute.for_product(product).map { |attribute| presenter.question(attribute) }
          }
        end

        def variant_label(variant)
          Spree::Review.new(variant: variant).variant_label
        end

        def limits
          { max_photos: Spree::Review::MAX_PHOTOS, max_photo_mb: Spree::Review::PHOTO_MAX_BYTES / 1.megabyte,
            title_max: Spree::Review::TITLE_MAX, body_max: Spree::Review::BODY_MAX,
            photo_types: Spree::Review::PHOTO_CONTENT_TYPES }
        end

        def per_page
          value = params[:per_page].to_i
          value.positive? ? [value, PER_PAGE_MAX].min : PER_PAGE_DEFAULT
        end
      end
    end
  end
end
