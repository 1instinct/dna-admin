module Spree
  module Api
    module V1
      module Admin
        # Service endpoints for AI review summaries (M7). Called by dna-frontend's
        # pages/api/internal/reviews/summarize.ts, never from a browser. Contract:
        # docs/plans/2026-11-26-reviews-api-contract.md, "M7 AI summaries".
        #
        #   GET /api/v1/admin/review_summaries/stale?limit=10          products needing a summary
        #   GET /api/v1/admin/products/:product_id/reviews_for_summary the summarizer's input
        #   PUT /api/v1/admin/review_summaries/:product_id             store a summary (JSON body)
        #
        # Auth: an admin user's API key as X-Spree-Token (the service credential; it doesn't
        # expire), or an admin's OAuth Bearer token. Neither resolving is 401; a non-admin user
        # (the storefront's own key, say) is 403. Logic lives in Reviews::AiSummaries.
        class ReviewSummariesController < Spree::Api::BaseController
          include Profiles::ApiResponses
          include Swagger::Blocks

          skip_before_action :authenticate_user
          before_action :require_admin
          before_action :load_product, only: %i[reviews_for_summary update]

          def stale
            stats = Reviews::AiSummaries.stale(limit: params[:limit], settings: settings)
            render json: { data: stats.map { |stat| Reviews::AiSummaries.stale_json(stat) } }
          end

          def reviews_for_summary
            render json: Reviews::AiSummaries.input_for(@product)
          end

          def update
            unless settings.ai_summary_enabled
              return render json: { error: 'AI summaries are switched off', code: 'not_enabled' }, status: :service_unavailable
            end

            attrs = parse_body
            return render_error('Body must be a JSON object', :unprocessable_entity, fields: { base: ['must be a JSON object'] }) unless attrs

            stat = Reviews::AiSummaries.store!(@product, attrs)
            render json: { ai_summary: Reviews::AiSummaries.summary_json(stat) }
          rescue Reviews::AiSummaries::Invalid => e
            render_error(e.message, :unprocessable_entity, fields: e.fields)
          end

          private

          def require_admin
            user = current_api_user
            return render_error('unauthorized', :unauthorized) unless user&.persisted?

            render_error('Admin only', :forbidden) unless user.has_spree_role?('admin')
          end

          def settings
            @settings ||= Spree::ReviewSetting.current
          end

          # A slug or an id; any product that isn't deleted.
          def load_product
            id = params[:product_id].to_s
            @product = Spree::Product.friendly.find(id)
          rescue ActiveRecord::RecordNotFound
            @product = id.match?(/\A\d+\z/) ? Spree::Product.find_by(id: id) : nil
            render_not_found unless @product
          end

          # The raw JSON body, so values keep their JSON types (params would coerce and wrap them).
          def parse_body
            body = JSON.parse(request.raw_post.presence || 'null')
            body.is_a?(Hash) ? body : nil
          rescue JSON::ParserError
            nil
          end

          swagger_path '/admin/review_summaries/stale' do
            operation :get do
              key :summary, 'Products whose AI review summary needs writing'
              key :description, 'Service endpoint for the storefront summarizer. Admin API key (X-Spree-Token) or admin Bearer. ' \
                                'Stale: at least ai_summary_min_reviews published retail reviews with text, not hidden, and no ' \
                                'summary yet, 3+ new written reviews, older than 30 days, or Regenerate pressed. Empty while AI ' \
                                'summaries are off.'
              key :tags, ['Reviews admin']
              parameter name: :limit, in: :query, required: false, type: :integer, minimum: 1, maximum: 25, default: 10
              response(200) { key :description, '{ data: [{ product_id, slug, name, reviews_count, summarized_count, generated_at }] }' }
              response(401) { key :description, 'Missing or invalid API key / token' }
              response(403) { key :description, 'Not an admin' }
            end
          end

          swagger_path '/admin/products/{product_id}/reviews_for_summary' do
            operation :get do
              key :summary, 'Input for a product AI review summary'
              key :description, 'The product (plain-text description, max 2000 chars), retail rating stats and up to 2000 ' \
                                'published retail reviews with text, newest first. The histogram counts star-only ratings too.'
              key :tags, ['Reviews admin']
              parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
              response(200) { key :description, '{ product, ratings_count, reviews_count, histogram, attributes, reviews }' }
              response(401) { key :description, 'Missing or invalid API key / token' }
              response(403) { key :description, 'Not an admin' }
              response(404) { key :description, 'Unknown product' }
            end
          end

          swagger_path '/admin/review_summaries/{product_id}' do
            operation :put do
              key :summary, 'Store a product AI review summary'
              key :description, 'JSON body: { headline (<= 80), summary (<= 600), pros/cons: [{ label (<= 40), mentions >= 1 }] ' \
                                '(<= 5 each), fit_consensus: runs_small|true_to_size|runs_large|null, review_count >= 1, model }. ' \
                                'HTML is stripped. Stored on the retail ReviewStat; clears a Regenerate request.'
              key :tags, ['Reviews admin']
              key :consumes, ['application/json']
              parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
              parameter name: :body, in: :body, required: true do
                schema do
                  key :type, :object
                  key :required, %w[headline summary pros cons review_count]
                  property(:headline) { key :type, :string }
                  property(:summary) { key :type, :string }
                  property(:pros) { key :type, :array }
                  property(:cons) { key :type, :array }
                  property(:fit_consensus) { key :type, :string }
                  property(:review_count) { key :type, :integer }
                  property(:model) { key :type, :string }
                end
              end
              response(200) { key :description, '{ ai_summary: { headline, summary, pros, cons, fit_consensus, model, review_count, generated_at, source_scope } }' }
              response(401) { key :description, 'Missing or invalid API key / token' }
              response(403) { key :description, 'Not an admin' }
              response(404) { key :description, 'Unknown product' }
              response(422) { key :description, '{ error, fields } for an invalid body' }
              response(503) { key :description, 'AI summaries are switched off (code: not_enabled)' }
            end
          end
        end
      end
    end
  end
end
