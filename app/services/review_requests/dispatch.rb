module ReviewRequests
  # One pass of `rake reviews:dispatch` (hourly). Every step re-reads the row under
  # `FOR UPDATE SKIP LOCKED` in its own transaction and re-checks its status, so two runs at once,
  # or a run repeated straight after, never send anything twice.
  #
  #   1. completed: sent/reminded requests whose order now has every item reviewed
  #   2. expired:   scheduled/sent/reminded requests past expires_at
  #   3. sent:      scheduled and due (send_after passed) -> fresh token, request email
  #   4. reminded:  sent, reminder_delay_days after sent_at, nothing reviewed -> fresh token, one reminder
  #
  # Steps 3 and 4 only run while reviews are switched on; a request that has nothing left to review
  # becomes completed (all reviewed) or cancelled (order canceled, no email, address opted out)
  # instead of being sent. A failed delivery is logged and rolls the row back (the new token
  # included), so the next run retries it.
  #
  #   ReviewRequests::Dispatch.call(now: Time.current) # => { sent: 3, reminded: 1, expired: 0, ... }
  class Dispatch
    COUNTS = %i[sent reminded expired completed cancelled failed].freeze

    def self.call(**args)
      new(**args).call
    end

    attr_reader :now, :settings, :counts

    def initialize(now: Time.current, settings: Spree::ReviewSetting.current, logger: Rails.logger)
      @now = now
      @settings = settings
      @logger = logger
      @counts = COUNTS.index_with { 0 }
    end

    def call
      complete_reviewed
      expire
      if settings.enabled
        send_due
        remind_due
      end
      # TODO(M7): ping the storefront to refresh stale AI summaries, e.g.
      #   POST "#{SITE_URL}/api/internal/reviews/summarize" with the shared secret.
      # Not built yet: see docs/plans/2026-11-26-product-reviews-plan.md (M7).
      counts
    end

    private

    def scope
      Spree::ReviewRequest
    end

    # Only requests with a review from their order can have become complete; the send and remind
    # steps check every other one themselves.
    def complete_reviewed
      candidates = scope.where(status: Spree::ReviewRequest::OPEN_STATUSES).
                   where(order_id: Spree::Review.for_products.where.not(order_id: nil).select(:order_id))
      each_locked(candidates) do |request|
        counts[:completed] += 1 if request.complete_if_reviewed!(now)
      end
    end

    def expire
      candidates = scope.where(status: %w[scheduled sent reminded]).where('expires_at <= ?', now)
      each_locked(candidates) do |request|
        request.update!(status: 'expired')
        counts[:expired] += 1
      end
    end

    def send_due
      each_locked(scope.due(now).where('expires_at IS NULL OR expires_at > ?', now)) do |request|
        items = sendable_items(request)
        next unless items

        token = request.issue_token!
        ReviewRequestMailer.request_review(request, token).deliver_now
        request.update!(status: 'sent', sent_at: now)
        counts[:sent] += 1
      end
    end

    def remind_due
      candidates = scope.where(status: 'sent').where('sent_at <= ?', now - settings.reminder_delay_days.days).
                   where('expires_at IS NULL OR expires_at > ?', now)
      each_locked(candidates) do |request|
        items = sendable_items(request)
        # "Nothing reviewed" only: someone who has started gets no reminder.
        next if items.nil? || items.any?(&:existing_review)

        token = request.issue_token!
        ReviewRequestMailer.reminder(request, token).deliver_now
        request.update!(status: 'reminded', reminded_at: now)
        counts[:reminded] += 1
      end
    end

    # The order's items when there is something to email about; otherwise closes the request
    # (completed or cancelled) and returns nil.
    def sendable_items(request)
      if request.email.blank? || Spree::ReviewRequest.opted_out?(request.email)
        return close(request, 'cancelled')
      end

      items = request.items
      return close(request, 'cancelled') if items.empty?
      return close(request, 'completed') if items.all?(&:existing_review)

      items
    end

    def close(request, status)
      attrs = { status: status }
      attrs[:completed_at] = now if status == 'completed'
      request.update!(attrs)
      counts[status.to_sym] += 1
      nil
    end

    # Yields each matching request locked in its own transaction, re-checked against `relation`
    # (a row another run has moved on no longer matches; one it holds is skipped). An error rolls
    # that request back and the loop carries on.
    def each_locked(relation)
      relation.order(:id).pluck(:id).each do |id|
        Spree::ReviewRequest.transaction do
          request = relation.lock('FOR UPDATE SKIP LOCKED').find_by(id: id)
          yield request if request
        end
      rescue StandardError => e
        counts[:failed] += 1
        @logger.error("[reviews] review request #{id} dispatch failed: #{e.class}: #{e.message}")
      end
    end
  end
end
