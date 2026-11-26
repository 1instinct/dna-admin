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
      class ReviewsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        WRITE_FIELDS = %i[rating title body display_name locale].freeze
        ERROR_STATUS = { not_enabled: :service_unavailable, not_eligible: :forbidden, forbidden: :forbidden,
                         invalid: :unprocessable_entity, not_found: :not_found }.freeze

        skip_before_action :authenticate_user
        before_action :reject_bad_bearer
        before_action :require_bearer_user, except: :votes
        before_action :load_own_review, only: %i[update destroy]
        before_action -> { enforce_rate_limit(:review) }, only: %i[create update]

        rescue_from Reviews::Error do |e|
          render json: { error: e.message, code: e.code.to_s }, status: ERROR_STATUS.fetch(e.code, :unprocessable_entity)
        end

        def create
          product = find_product(params.require(:product_id))
          return render_not_found unless product

          result = Reviews::Submit.call(reviewable: product, user: current_api_user, params: review_params,
                                        line_item_id: params[:line_item_id], ip: request.remote_ip, source: 'web')
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

          result = Reviews::Submit.call(reviewable: @review.reviewable, user: current_api_user,
                                        params: review_params, ip: request.remote_ip, source: @review.source)
          purge_photos(@review, removals) if result.success? && removals.any?
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
          @review = Spree::Review.find_by(id: params[:id], user_id: current_api_user.id)
          render_not_found unless @review
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
