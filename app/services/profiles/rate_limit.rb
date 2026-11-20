module Profiles
  # Per-user limits on actions that leave no row to count, or whose rows get deleted (a follow
  # toggled on and off). Limits are in Profiles.config.rate_limits, in a fixed window.
  #
  #   Profiles::RateLimit.allow?(user, :follow) # counts this attempt; false once over the limit
  #
  # Fails open: a counter error never takes the action down, and an unsaved user isn't counted.
  # Counters are one atomic upsert in Postgres, so they hold across dynos and restarts, need no
  # extra service and keep the table at one row per user and action.
  module RateLimit
    module_function

    def allow?(user, action, now: Time.current)
      return true unless user&.persisted?

      rule = Profiles.config.rate_limits.fetch(action)
      hit(user.id, action, rule[:window], now) <= rule[:limit]
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[profiles] rate limit check failed: #{e.class}")
      true
    end

    def hit(user_id, action, window, now)
      table = Spree::ProfileRateCounter.quoted_table_name
      sql = Spree::ProfileRateCounter.sanitize_sql_array([<<~SQL, { user_id: user_id, action: action.to_s, now: now, cutoff: now - window }])
        INSERT INTO #{table} (user_id, action, window_started_at, hits)
        VALUES (:user_id, :action, :now, 1)
        ON CONFLICT (user_id, action) DO UPDATE SET
          hits = CASE WHEN #{table}.window_started_at <= :cutoff THEN 1 ELSE #{table}.hits + 1 END,
          window_started_at = CASE WHEN #{table}.window_started_at <= :cutoff THEN :now ELSE #{table}.window_started_at END
        RETURNING hits
      SQL
      connection = Spree::ProfileRateCounter.connection
      connection.uncached { connection.select_value(sql) }.to_i
    end
  end
end
