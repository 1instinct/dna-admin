module ReviewRequests
  # Submissions through one email link (X-Review-Token): LIMIT per WINDOW, counting every attempt,
  # edits and refused ones included. A link only covers one order's items, so honest use stays
  # far below this.
  #
  # Reuses Profiles::RateLimit's atomic upsert counter (spree_profile_rate_counters). Rows are keyed
  # by the negated request id under their own action name, so they can never meet a user's
  # counters (user ids are positive; AccountDeletion clears only those). Fails open, like the
  # per-user limits.
  module RateLimit
    ACTION = 'review_link'.freeze
    LIMIT = 20
    WINDOW = 1.hour

    module_function

    def allow?(request, now: Time.current)
      return true unless request&.persisted?

      Profiles::RateLimit.hit(-request.id, ACTION, WINDOW, now) <= LIMIT
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[reviews] review link rate limit check failed: #{e.class}")
      true
    end
  end
end
