module Spree
  module Api
    module V1
      # Writing reviews. Contract: docs/plans/2026-11-26-reviews-api-contract.md ("M2 write path").
      #
      #   POST   /api/v1/reviews                 create, or edit the customer's review of that product
      #   PATCH  /api/v1/reviews/:id             edit (own review only; others are 404)
      #   DELETE /api/v1/reviews/:id             delete (own review only)
      #   POST   /api/v1/reviews/:id/votes       helpful / not helpful; Bearer or X-Visitor-Id
      #
      # Bearer required except for votes. 503 { code: not_enabled } while reviews are switched off;
      # 403 { code: not_eligible | forbidden }; 422 { error, fields }; 429 over the rate limits.
      #
      # The email link (M4): POST and PATCH also accept `X-Review-Token: <token>` instead of a Bearer.
      # The review is then for that request's order only (Reviews::Submit checks the item is on it),
      # stamped source "email", and belongs to the order's account if it has one; a Bearer sent along
      # never attaches a different account. PATCH reaches only reviews from that order or request.
      # An unknown or expired link is 404 { code: invalid_token }; 20 submissions an hour per link.
      # When every item on the order has a review, the request is marked completed.
      class ReviewsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        WRITE_FIELDS = %i[rating title body display_name locale].freeze
        ERROR_STATUS = { not_enabled: :service_unavailable, not_eligible: :forbidden, forbidden: :forbidden,
                         invalid: :unprocessable_entity, not_found: :not_found }.freeze

        skip_before_action :authenticate_user
        before_action :reject_bad_bearer
        before_action :load_review_request, only: %i[create update]
        before_action :require_bearer_user, except: :votes, unless: :review_link?
        before_action :load_own_review, only: %i[update destroy]
        before_action :enforce_review_rate_limit, only: %i[create update]

        rescue_from Reviews::Error do |e|
          render json: { error: e.message, code: e.code.to_s }, status: ERROR_STATUS.fetch(e.code, :unprocessable_entity)
        end

        def create
          product = find_product(params.require(:product_id))
          return render_not_found unless product

          result = Reviews::Submit.call(reviewable: product, user: submitting_user, review_request: @review_request,
                                        params: review_params, line_item_id: params[:line_item_id],
                                        ip: request.remote_ip, source: review_link? ? 'email' : 'web')
          complete_review_request if result.success?
          render_result(result, created_status: :created)
        end

        def update
          removals = removal_ids
          photos = Array(params[:photos]).select { |file| file.respond_to?(:read) }
          remaining = @review.photos.count - @review.photos.where(id: removals).count + photos.size
          if remaining > Spree::Review::MAX_PHOTOS
            return render_error("A review can have up to #{Spree::Review::MAX_PHOTOS} photos", :unprocessable_entity,
                                fields: { photos: ["can't be more than #{Spree::Review::MAX_PHOTOS}"] })
          end

          result = Reviews::Submit.call(reviewable: @review.reviewable, user: submitting_user,
                                        review_request: @review_request, params: review_params,
                                        ip: request.remote_ip, source: @review.source)
          purge_photos(@review, removals) if result.success? && removals.any?
          complete_review_request if result.success?
          render_result(result, created_status: :ok)
        end

        def destroy
          was_published = @review.published?
          reviewable = @review.reviewable
          blobs = @review.photos.map(&:blob)
          @review.photos.each(&:delete)
          @review.destroy!
          Reviews::RefreshStats.call(reviewable) if was_published && reviewable
          purge_blobs(blobs)
          head :no_content
        end

        def votes
          review = Spree::Review.published.find_by(id: params[:id])
          return render_not_found unless review

          voter = viewer if bearer_token.present?
          if voter && review.user_id == voter.id
            return render_error("You can't vote on your own review", :unprocessable_entity)
          end
          if voter && !Profiles::RateLimit.allow?(voter, :review_vote)
            return render_error('Too many requests. Try again later.', :too_many_requests)
          end

          helpful = ActiveModel::Type::Boolean.new.cast(params[:helpful])
          return render_error('helpful must be true or false', :unprocessable_entity) if helpful.nil?

          review = Reviews::Votes.cast(review, helpful: helpful, user: voter, visitor_id: visitor_id)
          render json: { helpful_count: review.helpful_count, unhelpful_count: review.unhelpful_count, your_vote: helpful }
        end

        private

        # A Bearer token that doesn't resolve to an active user is refused rather than ignored.
        def reject_bad_bearer
          render_error('unauthorized', :unauthorized) if bearer_token.present? && current_api_user.nil?
        end

        def presenter
          @presenter ||= Reviews::Presenter.new(base_url: request.base_url)
        end

        def find_product(id)
          scope = Spree::Product.publicly_visible
          scope.friendly.find(id.to_s)
        rescue ActiveRecord::RecordNotFound
          id.to_s.match?(/\A\d+\z/) ? scope.find_by(id: id) : nil
        end

        def load_own_review
          @review = if review_link?
                      Spree::Review.where(id: params[:id]).
                        where('review_request_id = ? OR order_id = ?', @review_request.id, @review_request.order_id).first
                    else
                      Spree::Review.find_by(id: params[:id], user_id: current_api_user.id)
                    end
          render_not_found unless @review
        end

        def review_token
          request.headers['X-Review-Token'].to_s.strip.presence
        end

        # Only create and update take the email link; elsewhere the header is ignored.
        def review_link?
          @review_request.present?
        end

        def load_review_request
          return unless review_token

          @review_request = Spree::ReviewRequest.find_for_link(review_token)
          return if @review_request

          render json: { error: "This review link isn't valid any more", code: 'invalid_token' }, status: :not_found
        end

        # With the email link the review belongs to the order's buyer (nil for a guest checkout),
        # whoever else is signed in.
        def submitting_user
          review_link? ? @review_request.order.user : current_api_user
        end

        def enforce_review_rate_limit
          return enforce_rate_limit(:review) unless review_link?
          return if ReviewRequests::RateLimit.allow?(@review_request)

          render_error('Too many requests. Try again later.', :too_many_requests)
        end

        # The page was opened if a review came through it; completed once every item is reviewed.
        def complete_review_request
          return unless review_link?

          @review_request.update_column(:opened_at, Time.current) if @review_request.opened_at.nil?
          @review_request.complete_if_reviewed!
        rescue StandardError => e
          Rails.logger.error("[reviews] review request #{@review_request.id} completion check failed: #{e.class}")
        end

        def review_params
          attrs = params.permit(*WRITE_FIELDS).to_h.symbolize_keys
          attrs[:attribute_ratings] = params[:attribute_ratings].to_unsafe_h if params[:attribute_ratings].respond_to?(:to_unsafe_h)
          photos = Array(params[:photos]).select { |file| file.respond_to?(:read) }
          attrs[:photos] = photos if photos.any?
          attrs
        end

        def removal_ids
          Array(params[:remove_photo_ids]).map { |id| Integer(id, exception: false) }.compact
        end

        def render_result(result, created_status:)
          return render_record_errors(result.review, 'Review could not be saved') unless result.success?

          render json: { review: presenter.own_review(result.review.reload) },
                 status: result.created ? created_status : :ok
        end

        def purge_photos(review, ids)
          attachments = review.photos.where(id: ids).to_a
          blobs = attachments.map(&:blob)
          attachments.each(&:delete)
          Reviews::RefreshStats.call(review.reviewable) if review.reload.published?
          purge_blobs(blobs)
        end

        # Inline: there is no persistent job queue, and a storage failure shouldn't fail the request.
        def purge_blobs(blobs)
          blobs.each do |blob|
            blob.purge
          rescue StandardError => e
            Rails.logger.error("[reviews] blob_key=#{blob.key} purge failed: #{e.class}")
          end
        end

        def visitor_id
          request.headers['X-Visitor-Id'].to_s.strip.first(100).presence
        end
      end
    end
  end
end
