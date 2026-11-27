module Spree
  module Api
    module V1
      # Product questions (M6). Contract: docs/plans/2026-11-26-reviews-api-contract.md ("M6 questions").
      #
      #   GET  /api/v1/products/:product_id/questions?page=&per_page=   answered questions, newest answer first
      #   POST /api/v1/products/:product_id/questions                   Bearer: ask one { body, display_name? }
      #
      # Only answered questions are public: a question with no published answer is never listed or
      # counted. Asked questions wait as pending until staff answer them in admin (Reviews >
      # Questions), which emails the asker. :product_id is a slug or an id; products the public
      # can't see are 404. 503 { code: not_enabled } while reviews or questions are off.
      class ProductQuestionsController < Spree::Api::BaseController
        include Profiles::ApiResponses
        include Swagger::Blocks

        PER_PAGE_DEFAULT = 5
        PER_PAGE_MAX = 20
        THANKS = "Thanks! We'll email you when it's answered.".freeze

        skip_before_action :authenticate_user
        before_action :reject_bad_bearer
        before_action :require_enabled
        before_action :require_bearer_user, only: :create
        before_action :load_product

        def index
          page = Spree::ProductQuestion.answered.where(product_id: @product.id).by_latest_answer.
                 page([params[:page].to_i, 1].max).per(per_page)
          questions = page.to_a
          answers = Spree::ProductAnswer.published.where(question_id: questions.map(&:id)).display_order.group_by(&:question_id)
          store_name = Reviews::Questions.store_name

          render json: {
            data: questions.map { |question| Reviews::Questions.json(question, answers.fetch(question.id, []), store_name: store_name) },
            meta: { page: page.current_page, per_page: page.limit_value, total_count: page.total_count,
                    total_pages: page.total_pages }
          }
        end

        def create
          user = current_api_user
          question = Spree::ProductQuestion.new(
            product: @product, user: user, status: 'pending', body: params[:body].to_s.strip,
            display_name: params[:display_name].to_s.strip.presence || default_display_name(user)
          )
          return render_record_errors(question, question.errors.full_messages.first) unless question.valid?
          # Counted once the question is valid: 5 questions a day, not 5 attempts.
          unless Profiles::RateLimit.allow?(user, :question)
            return render_error('Too many questions today. Try again tomorrow.', :too_many_requests)
          end

          question.save!
          render json: { id: question.id, status: question.status, message: THANKS }, status: :created
        end

        private

        def settings
          @settings ||= Spree::ReviewSetting.current
        end

        def require_enabled
          return if settings.enabled && settings.questions_enabled

          render json: { error: 'Questions are switched off', code: 'not_enabled' }, status: :service_unavailable
        end

        # A Bearer token that doesn't resolve to an active user is refused rather than ignored.
        def reject_bad_bearer
          render_error('unauthorized', :unauthorized) if bearer_token.present? && current_api_user.nil?
        end

        def load_product
          scope = Spree::Product.publicly_visible
          id = params[:product_id].to_s
          @product = scope.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          @product = id.match?(/\A\d+\z/) ? scope.find_by(id: id) : nil
          render_not_found unless @product
        end

        # "Maya R.", like reviews: from the customer's latest order's address, else their address book.
        def default_display_name(user)
          order = user.orders.complete.reorder(completed_at: :desc).first
          Spree::Review.default_display_name(order: order, user: user)
        end

        def per_page
          value = params[:per_page].to_i
          value.positive? ? [value, PER_PAGE_MAX].min : PER_PAGE_DEFAULT
        end

        swagger_path '/products/{product_id}/questions' do
          operation :get do
            key :summary, 'Answered questions about a product'
            key :description, 'Only questions with a published answer; newest answer first. Answers: official first, then oldest first. ' \
                              '503 { code: not_enabled } while reviews or questions are off.'
            key :tags, ['Questions']
            parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
            parameter name: :page, in: :query, required: false, type: :integer
            parameter name: :per_page, in: :query, required: false, type: :integer, description: '1-20, default 5'
            response(200) { key :description, '{ data: [{ id, body, display_name, asked_at, answers: [...] }], meta }' }
            response(404) { key :description, 'Unknown or hidden product' }
            response(503) { key :description, 'Reviews or questions switched off' }
          end

          operation :post do
            key :summary, 'Ask a question about a product'
            key :description, 'Bearer. JSON { body (10-500 chars), display_name? (default "First L.") }. ' \
                              'Stays pending until staff answer it; the asker is emailed then. 5 a day per account.'
            key :tags, ['Questions']
            key :consumes, ['application/json']
            parameter name: :product_id, in: :path, required: true, type: :string, description: 'Product slug or id'
            parameter name: :Authorization, in: :header, required: true, type: :string, description: 'Bearer <token>'
            parameter name: :body, in: :formData, required: true, type: :string
            parameter name: :display_name, in: :formData, required: false, type: :string
            response(201) { key :description, '{ id, status: "pending", message }' }
            response(401) { key :description, 'No Bearer' }
            response(404) { key :description, 'Unknown or hidden product' }
            response(422) { key :description, '{ error, fields }' }
            response(429) { key :description, 'More than 5 questions today' }
            response(503) { key :description, 'Reviews or questions switched off' }
          end
        end
      end
    end
  end
end
