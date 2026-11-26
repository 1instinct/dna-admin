module Spree
  module Admin
    # Reviews > Review emails: the post-purchase review requests (ReviewRequests::Schedule /
    # Dispatch), newest first, filterable by status, with the last 30 days' funnel
    # (sent -> opened -> completed). Read-only: `rake reviews:dispatch` moves requests along.
    class ReviewRequestsController < Spree::Admin::BaseController
      PER_PAGE = 50
      FUNNEL_DAYS = 30

      def index
        @status = Spree::ReviewRequest::STATUSES.include?(params[:status]) ? params[:status] : nil
        scope = Spree::ReviewRequest.includes(:order).order(created_at: :desc, id: :desc)
        scope = scope.where(status: @status) if @status
        @review_requests = scope.page(params[:page]).per(PER_PAGE)
        @status_counts = Spree::ReviewRequest.group(:status).count
        @funnel = funnel
      end

      private

      def model_class
        Spree::ReviewRequest
      end

      # Of the requests first sent in the last 30 days: how many were opened, and how many have a
      # review for every item.
      def funnel
        sent = Spree::ReviewRequest.where('sent_at >= ?', FUNNEL_DAYS.days.ago)
        total = sent.count
        opened = sent.where.not(opened_at: nil).count
        completed = sent.where.not(completed_at: nil).count
        { days: FUNNEL_DAYS, sent: total, opened: opened, completed: completed,
          opened_pct: percent(opened, total), completed_pct: percent(completed, total) }
      end

      def percent(part, total)
        total.zero? ? 0 : (part * 100.0 / total).round
      end
    end
  end
end
