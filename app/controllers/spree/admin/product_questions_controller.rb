module Spree
  module Admin
    # Reviews > Questions: shoppers' product questions (waiting first by default) and the answer
    # form. An answer from here is official and published at once; it publishes the question,
    # which then shows on the product page, and emails the asker (Reviews::Questions.answer!).
    # Rejecting sends no email. Removing the last answer sends the question back to the queue.
    class ProductQuestionsController < Spree::Admin::BaseController
      PER_PAGE = 50
      STATUS_FILTERS = (%w[all] + Spree::ProductQuestion::STATUSES).freeze

      before_action :load_question, except: :index

      def index
        @filters = filter_params
        @questions = filtered(Spree::ProductQuestion.includes(:product, :user)).
                     order(created_at: :desc, id: :desc).page(params[:page]).per(PER_PAGE)
        @counts = Spree::ProductQuestion.group(:status).count
      end

      def show
        @answers = @question.answers.includes(:user).display_order
      end

      def answer
        body = params[:answer_body].to_s.strip
        if body.blank?
          flash[:error] = 'Write an answer first.'
          return redirect_to(spree.admin_product_question_path(@question))
        end

        answer = Reviews::Questions.answer!(@question, body: body, by: try_spree_current_user)
        if answer.persisted?
          emailed = @question.user&.email.present?
          flash[:success] = emailed ? 'Answer published. We emailed the customer.' : 'Answer published.'
        else
          flash[:error] = answer.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_product_question_path(@question)
      end

      def reject
        Reviews::Questions.reject!(@question)
        flash[:success] = 'Question rejected'
        redirect_to spree.admin_product_question_path(@question)
      end

      def destroy_answer
        answer = @question.answers.find_by(id: params[:answer_id])
        if answer
          Reviews::Questions.remove_answer!(answer)
          flash[:success] = 'Answer removed'
        else
          flash[:error] = 'That answer is already gone'
        end
        redirect_to spree.admin_product_question_path(@question)
      end

      private

      def model_class
        Spree::ProductQuestion
      end

      def load_question
        @question = Spree::ProductQuestion.find(params[:id])
      end

      def filter_params
        f = params.permit(:status, :q).to_h.symbolize_keys
        f[:status] = 'pending' unless STATUS_FILTERS.include?(f[:status])
        f
      end

      def filtered(scope)
        scope = scope.where(status: @filters[:status]) unless @filters[:status] == 'all'
        return scope if @filters[:q].blank?

        like = "%#{Spree::ProductQuestion.sanitize_sql_like(@filters[:q].strip)}%"
        product_ids = Spree::Product.with_deleted.where('spree_products.name ILIKE ?', like).select(:id)
        scope.where(product_id: product_ids).
          or(scope.where('spree_product_questions.body ILIKE :q OR spree_product_questions.display_name ILIKE :q', q: like))
      end
    end
  end
end
