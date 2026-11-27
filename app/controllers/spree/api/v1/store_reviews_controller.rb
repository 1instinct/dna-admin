module Spree
  module Api
    module V1
      # Reviews of the store itself (M5). Contract: docs/plans/2026-11-26-reviews-api-contract.md ("M5 store reviews").
      #
      #   GET   /api/v1/store_reviews/summary   rating summary (retail), with the store questions
      #   GET   /api/v1/store_reviews           published retail store reviews; sort, rating[], written, paging
      #   GET   /api/v1/store_reviews/form      Bearer: what the composer needs, and the customer's review
      #   POST  /api/v1/store_reviews           Bearer or X-Review-Token: write one
      #   PATCH /api/v1/store_reviews/:id       Bearer or X-Review-Token: edit it
      #
      # A store review is a Spree::Review of Reviews.store, through the same Reviews::Submit,
      # moderation and own-review shape as product reviews, but with no photos (422), no points
      # and no product. One per account with a Bearer, one per order with the email link; a second
      # POST is 409 { code: already_reviewed, review_id }. Wholesale store reviews are never listed.
      # Every endpoint is 503 { code: not_enabled } while reviews or store reviews are off.
      class StoreReviewsController < Spree::Api::BaseController
        include Profiles::ApiResponses
        include Swagger::Blocks

        WRITE_FIELDS = %i[rating title body display_name locale].freeze
        SORTS = Spree::Api::V1::ProductReviewsController::SORTS
        PER_PAGE_DEFAULT = 10
        PER_PAGE_MAX = 50
        ERROR_STATUS = { not_enabled: :service_unavailable, not_eligible: :forbidden, forbidden: :forbidden,
                         invalid: :unprocessable_entity, not_found: :not_found }.freeze

        skip_before_action :authenticate_user
        before_action :reject_bad_bearer
        before_action :require_enabled
        before_action :load_store
        before_action :load_review_request, only: %i[create update]
        # The form always needs a Bearer; writes take the email link instead.
        before_action :require_bearer_user, only: %i[form create update], unless: :review_link?
        before_action :reject_photos, only: %i[create update]
        before_action :load_own_review, only: :update
        before_action :enforce_review_rate_limit, only: %i[create update]

        rescue_from Reviews::Error do |e|
          render json: { error: e.message, code: e.code.to_s }, status: ERROR_STATUS.fetch(e.code, :unprocessable_entity)
        end

        # Same shape as a product's review_summary, retail only, with no photos or AI summary.
        def summary
          render json: presenter.summary(@store, 'retail').except(:latest_photos).merge(ai_summary: nil)
        end

        def index
          reviews = Spree::Review.published.where(reviewable: @store).retail
          reviews = reviews.where(rating: ratings) if ratings.any?
          reviews = reviews.written if truthy?(params[:written])
          page = reviews.order(Arel.sql(SORTS.fetch(params[:sort].to_s, SORTS['helpful']))).
                 includes(:reviewable, photos_attachments: :blob).
                 page([params[:page].to_i, 1].max).per(per_page)

          render json: {
            data: page.map { |review| presenter.review(review).merge(variant_label: nil) },
            meta: { page: page.current_page, per_page: page.limit_value, total_count: page.total_count,
                    total_pages: page.total_pages, scope: 'retail' }
          }
        end

        def form
          user = current_api_user
          order = Reviews::Eligibility.latest_shipped_order(user)
          existing = own_store_review(user)
          render json: {
            eligible: order.present?,
            reason: order ? nil : 'no_shipped_order',
            display_name: existing&.display_name || Spree::Review.default_display_name(order: order, user: user),
            questions: Spree::ReviewAttribute.for_store.map { |attribute| presenter.question(attribute) },
            existing_review: existing && own_review_json(existing),
            limits: { title_max: Spree::Review::TITLE_MAX, body_max: Spree::Review::BODY_MAX }
          }
        end

        def create
          existing = existing_review_for_create
          if existing
            return render json: { error: "You've already reviewed us. Edit that review instead.", code: 'already_reviewed',
                                  review_id: existing.id }, status: :conflict
          end

          result = Reviews::Submit.call(reviewable: @store, user: submitting_user, review_request: @review_request,
                                        params: review_params, ip: request.remote_ip, source: review_link? ? 'email' : 'web')
          mark_review_request_opened if result.success?
          render_result(result)
        end

        def update
          result = Reviews::Submit.call(reviewable: @store, user: submitting_user, review_request: @review_request,
                                        params: review_params, ip: request.remote_ip, source: @review.source)
          mark_review_request_opened if result.success?
          render_result(result)
        end

        private

        def settings
          @settings ||= Spree::ReviewSetting.current
        end

        def require_enabled
          return if settings.enabled && settings.store_reviews_enabled

          render json: { error: 'Store reviews are switched off', code: 'not_enabled' }, status: :service_unavailable
        end

        def load_store
          @store = Reviews.store
          render_not_found unless @store
        end

        # A Bearer token that doesn't resolve to an active user is refused rather than ignored.
        def reject_bad_bearer
          render_error('unauthorized', :unauthorized) if bearer_token.present? && current_api_user.nil?
        end

        def presenter
          @presenter ||= Reviews::Presenter.new(base_url: Reviews.asset_base_url(request))
        end

        def own_review_json(review)
          presenter.own_review(review, settings: settings).merge(variant_label: nil)
        end

        def own_store_review(user)
          user && Spree::Review.where(reviewable: @store).find_by(user_id: user.id)
        end

        # Bearer: the account's store review. Email link: this order's, or its buyer's account's
        # (an account has one store review whichever way it was written).
        def existing_review_for_create
          scope = Spree::Review.where(reviewable: @store)
          return own_store_review(current_api_user) unless review_link?

          order = @review_request.order
          scope.find_by(order_id: order.id) || (order.user_id && scope.find_by(user_id: order.user_id))
        end

        def load_own_review
          scope = Spree::Review.where(reviewable: @store)
          @review = if review_link?
                      scope.where(id: params[:id]).
                        where('review_request_id = ? OR order_id = ?', @review_request.id, @review_request.order_id).first
                    else
                      scope.find_by(id: params[:id], user_id: current_api_user.id)
                    end
          render_not_found unless @review
        end

        def review_token
          request.headers['X-Review-Token'].to_s.strip.presence
        end

        def review_link?
          @review_request.present?
        end

        def load_review_request
          return unless review_token

          @review_request = Spree::ReviewRequest.find_for_link(review_token)
          return if @review_request

          render json: { error: "This review link isn't valid any more", code: 'invalid_token' }, status: :not_found
        end

        # With the email link the review belongs to the order's buyer (nil for a guest checkout).
        def submitting_user
          review_link? ? @review_request.order.user : current_api_user
        end

        def reject_photos
          return unless params.key?(:photos) || params.key?('photos[]')

          render json: { error: "Store reviews can't have photos", code: 'invalid',
                         fields: { photos: ["aren't allowed on store reviews"] } }, status: :unprocessable_entity
        end

        def enforce_review_rate_limit
          return enforce_rate_limit(:review) unless review_link?
          return if ReviewRequests::RateLimit.allow?(@review_request)

          render_error('Too many requests. Try again later.', :too_many_requests)
        end

        # A store review shows the page was opened. It never completes the request: only product
        # reviews count toward that (Spree::ReviewRequest#complete_if_reviewed!).
        def mark_review_request_opened
          return unless review_link? && @review_request.opened_at.nil?

          @review_request.update_column(:opened_at, Time.current)
        end

        def review_params
          attrs = params.permit(*WRITE_FIELDS).to_h.symbolize_keys
          attrs[:attribute_ratings] = params[:attribute_ratings].to_unsafe_h if params[:attribute_ratings].respond_to?(:to_unsafe_h)
          attrs
        end

        def render_result(result)
          return render_record_errors(result.review, 'Review could not be saved') unless result.success?

          render json: { review: own_review_json(result.review.reload) }, status: result.created ? :created : :ok
        end

        def ratings
          @ratings ||= Array(params[:rating]).map { |value| Integer(value, exception: false) }.compact.select { |n| n.between?(1, 5) }.uniq
        end

        def per_page
          value = params[:per_page].to_i
          value.positive? ? [value, PER_PAGE_MAX].min : PER_PAGE_DEFAULT
        end

        def truthy?(value)
          ActiveModel::Type::Boolean.new.cast(value) == true
        end

        swagger_path '/store_reviews/summary' do
          operation :get do
            key :summary, 'Rating summary for the store'
            key :description, 'Retail store reviews: average, histogram and store questions (delivery, packaging). ' \
                              'Same shape as a product review_summary, without latest_photos; ai_summary is null. ' \
                              '503 { code: not_enabled } while reviews or store reviews are off.'
            key :tags, ['Store reviews']
            response(200) { key :description, 'Summary' }
            response(503) { key :description, 'Reviews or store reviews switched off' }
          end
        end

        swagger_path '/store_reviews' do
          operation :get do
            key :summary, 'Published store reviews'
            key :description, 'Retail only; wholesale store reviews are never listed. Default sort is most helpful.'
            key :tags, ['Store reviews']
            parameter name: :sort, in: :query, required: false, type: :string, enum: SORTS.keys
            parameter name: 'rating[]', in: :query, required: false, type: :array, items: { type: :integer },
                      collectionFormat: :multi
            parameter name: :written, in: :query, required: false, type: :boolean
            parameter name: :page, in: :query, required: false, type: :integer
            parameter name: :per_page, in: :query, required: false, type: :integer
            response(200) { key :description, '{ data: [review], meta: { page, per_page, total_count, total_pages, scope } }' }
            response(503) { key :description, 'Reviews or store reviews switched off' }
          end

          operation :post do
            key :summary, 'Write a store review'
            key :description, 'Bearer, or X-Review-Token (the email link; the review is tied to that order, source email). ' \
                              'JSON { rating, title?, body?, attribute_ratings?, display_name? }. No photos, no points. ' \
                              'One per account (Bearer) or per order (link): a second POST is 409.'
            key :tags, ['Store reviews']
            key :consumes, ['application/json']
            parameter name: :Authorization, in: :header, required: false, type: :string, description: 'Bearer <token>'
            parameter name: 'X-Review-Token', in: :header, required: false, type: :string, description: 'Review link token'
            parameter name: :rating, in: :formData, required: true, type: :integer
            parameter name: :title, in: :formData, required: false, type: :string
            parameter name: :body, in: :formData, required: false, type: :string
            parameter name: :display_name, in: :formData, required: false, type: :string
            response(201) { key :description, '{ review: own review } (product null, points 0)' }
            response(401) { key :description, 'No Bearer and no review link' }
            response(403) { key :description, 'not_eligible (no shipped order) or forbidden (staff)' }
            response(404) { key :description, 'invalid_token' }
            response(409) { key :description, '{ code: already_reviewed, review_id }' }
            response(422) { key :description, '{ error, fields } or code invalid (photos, unknown question)' }
            response(429) { key :description, 'Rate limited' }
            response(503) { key :description, 'Reviews or store reviews switched off' }
          end
        end

        swagger_path '/store_reviews/form' do
          operation :get do
            key :summary, 'Store review composer data'
            key :description, 'Bearer. { eligible, reason (no_shipped_order), display_name, questions, existing_review, limits }.'
            key :tags, ['Store reviews']
            parameter name: :Authorization, in: :header, required: true, type: :string, description: 'Bearer <token>'
            response(200) { key :description, 'Form' }
            response(401) { key :description, 'No Bearer' }
            response(503) { key :description, 'Reviews or store reviews switched off' }
          end
        end

        swagger_path '/store_reviews/{id}' do
          operation :patch do
            key :summary, 'Edit your store review'
            key :description, 'Bearer (your review) or X-Review-Token (that order\'s review). Goes back through moderation.'
            key :tags, ['Store reviews']
            key :consumes, ['application/json']
            parameter name: :id, in: :path, required: true, type: :integer
            parameter name: :Authorization, in: :header, required: false, type: :string, description: 'Bearer <token>'
            parameter name: 'X-Review-Token', in: :header, required: false, type: :string, description: 'Review link token'
            parameter name: :rating, in: :formData, required: false, type: :integer
            parameter name: :title, in: :formData, required: false, type: :string
            parameter name: :body, in: :formData, required: false, type: :string
            parameter name: :display_name, in: :formData, required: false, type: :string
            response(200) { key :description, '{ review: own review }' }
            response(404) { key :description, 'Not your review, or invalid_token' }
            response(422) { key :description, '{ error, fields }' }
            response(503) { key :description, 'Reviews or store reviews switched off' }
          end
        end
      end
    end
  end
end
