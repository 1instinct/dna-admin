module Spree
  module Api
    module V1
      # The email link's review page (/review/[token] on the storefront). No login: the token from
      # the email proves the purchase. Contract: docs/plans/2026-11-26-reviews-api-contract.md ("M4 email flow").
      #
      #   GET  /api/v1/review_requests/:token           the order's items to review; sets opened_at once
      #   POST /api/v1/review_requests/:token/opt_out   no more review emails for this address (any
      #                                                 request with this token, whatever its state)
      #
      # GET answers for sent, reminded and completed requests until they expire (a completed link
      # still shows what was reviewed and allows edits); anything else is 404. Reviews are written
      # with POST/PATCH /api/v1/reviews and the X-Review-Token header.
      #
      # The route param is :review_token, not :token: Spree's API base controller reads
      # params[:token] as an API key.
      class ReviewRequestsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        skip_before_action :authenticate_user

        def show
          unless settings.enabled
            return render json: { error: 'Reviews are switched off', code: 'not_enabled' }, status: :service_unavailable
          end

          review_request = Spree::ReviewRequest.find_for_link(params[:review_token])
          return render_not_found unless review_request

          review_request.update_column(:opened_at, Time.current) if review_request.opened_at.nil?
          render json: payload(review_request)
        end

        def opt_out
          token = params[:review_token].to_s
          review_request = token.present? && Spree::ReviewRequest.find_by(token_digest: Spree::ReviewRequest.digest(token))
          return render_not_found unless review_request

          # Whatever state the request is in: opting out is about the address, and Schedule and
          # Dispatch skip any address with an opted-out request.
          review_request.update!(status: 'opted_out') unless review_request.status == 'opted_out'
          render json: { status: review_request.status }
        end

        private

        def settings
          @settings ||= Spree::ReviewSetting.current
        end

        def presenter
          @presenter ||= Reviews::Presenter.new(base_url: request.base_url)
        end

        def payload(review_request)
          order = review_request.order
          {
            order_number: order.number,
            display_name: Spree::Review.default_display_name(order: order, user: order.user),
            items: review_request.items.map { |item| item_json(item) },
            store_review: {
              enabled: settings.store_reviews_enabled,
              existing_review: store_review(order)
            },
            points: presenter.points_offer(settings),
            has_account: order.user_id.present?,
            limits: presenter.limits
          }
        end

        def item_json(item)
          product = item.product
          review = item.existing_review
          {
            line_item_id: item.line_item.id,
            product_id: product.id,
            slug: product.slug,
            name: product.name,
            image_url: presenter.product(product)[:image_url],
            variant_label: Spree::Review.new(variant: item.variant).variant_label,
            questions: Spree::ReviewAttribute.for_product(product).map { |attribute| presenter.question(attribute) },
            existing_review: review && presenter.own_review(review, settings: settings)
          }
        end

        def store_review(order)
          review = Spree::Review.for_store.find_by(order_id: order.id)
          review && presenter.own_review(review, settings: settings)
        end
      end
    end
  end
end
