module Spree
  module Admin
    # The "Feedback" tab: app feedback, newest first. Filters: kind, rating, platform, app version,
    # status (default: everything but archived), has screenshot, and a created-at date range.
    # Each item can be triaged (status + admin note); a selection can be archived in bulk.
    class AppFeedbacksController < Spree::Admin::BaseController
      PER_PAGE = 50
      STATUS_FILTERS = (%w[active all] + AppFeedback::STATUSES).freeze

      before_action :load_feedback, only: %i[show update]

      def index
        @filters = filter_params
        @feedbacks = filtered(AppFeedback.includes(:screenshot_attachment).newest_first)
                     .page(params[:page]).per(PER_PAGE)
        @platforms = AppFeedback.where.not(platform: [nil, '']).distinct.order(:platform).pluck(:platform)
        @app_versions = sorted_versions(AppFeedback.where.not(app_version: [nil, '']).distinct.pluck(:app_version)).first(50)
      end

      def show; end

      def update
        attrs = params.require(:app_feedback).permit(:status, :admin_note)
        attrs[:admin_note] = attrs[:admin_note].to_s.strip.presence if attrs.key?(:admin_note)
        if @feedback.update(attrs)
          flash[:success] = 'Feedback updated'
        else
          flash[:error] = @feedback.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_app_feedback_path(@feedback)
      end

      def bulk_archive
        ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
        count = ids.any? ? AppFeedback.where(id: ids).where.not(status: 'archived').update_all(status: 'archived', updated_at: Time.current) : 0
        flash[:success] = "Archived #{count} #{'item'.pluralize(count)}"
        redirect_back fallback_location: spree.admin_app_feedbacks_path
      end

      private

      def model_class
        AppFeedback
      end

      def load_feedback
        @feedback = AppFeedback.find(params[:id])
      end

      def filter_params
        f = params.permit(:kind, :rating, :platform, :app_version, :status, :screenshot, :from, :to).to_h.symbolize_keys
        f[:status] = 'active' unless STATUS_FILTERS.include?(f[:status])
        f
      end

      def filtered(scope)
        f = @filters
        scope = scope.where(kind: f[:kind]) if AppFeedback::KINDS.include?(f[:kind])
        scope = scope.where(rating: f[:rating].to_i) if (1..5).cover?(f[:rating].to_i)
        scope = scope.where(platform: f[:platform]) if f[:platform].present?
        scope = scope.where(app_version: f[:app_version]) if f[:app_version].present?
        case f[:status]
        when 'active' then scope = scope.where.not(status: 'archived')
        when 'all' then nil
        else scope = scope.where(status: f[:status])
        end
        scope = scope.with_screenshot if f[:screenshot] == 'yes'
        scope = scope.without_screenshot if f[:screenshot] == 'no'
        from = parse_date(f[:from])
        to = parse_date(f[:to])
        scope = scope.where('app_feedbacks.created_at >= ?', from.beginning_of_day) if from
        scope = scope.where('app_feedbacks.created_at <= ?', to.end_of_day) if to
        scope
      end

      # Newest first by version ("1.10.0" above "1.9.0"); values that aren't versions go last, A-Z.
      def sorted_versions(versions)
        valid, junk = versions.partition { |v| Gem::Version.correct?(v.to_s.strip) }
        valid.sort_by { |v| Gem::Version.new(v.to_s.strip) }.reverse + junk.sort
      end

      def parse_date(value)
        Date.iso8601(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
