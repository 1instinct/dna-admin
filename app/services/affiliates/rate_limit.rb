module Affiliates
  # Fixed-window counters keyed by string (e.g. "click:<visitor hash>"), with the limits in
  # Affiliates.config.rate_limits. Same design as Profiles::RateLimit: one atomic upsert per check
  # in Postgres, so limits hold across dynos and restarts with no extra service.
  #
  #   Affiliates::RateLimit.allow?(:click, visitor_hash) # counts this attempt; false once over
  #
  # Fails open: a counter error never takes the endpoint down.
  module RateLimit
    module_function

    def allow?(rule_name, key, now: Time.current)
      return true if key.blank?

      rule = Affiliates.config.rate_limits.fetch(rule_name)
      hit("#{rule_name}:#{key}", rule[:window], now) <= rule[:limit]
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[affiliates] rate limit check failed: #{e.class}")
      true
    end

    def hit(key, window, now)
      table = ActiveRecord::Base.connection.quote_table_name('affiliate_rate_counters')
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, { key: key, now: now, cutoff: now - window }])
        INSERT INTO #{table} (key, window_started_at, hits)
        VALUES (:key, :now, 1)
        ON CONFLICT (key) DO UPDATE SET
          hits = CASE WHEN #{table}.window_started_at <= :cutoff THEN 1 ELSE #{table}.hits + 1 END,
          window_started_at = CASE WHEN #{table}.window_started_at <= :cutoff THEN :now ELSE #{table}.window_started_at END
        RETURNING hits
      SQL
      connection = ActiveRecord::Base.connection
      hits = connection.uncached { connection.select_value(sql) }.to_i
      prune(now - (2 * window)) if rand < 0.01
      hits
    end

    # Drops counters whose window ended long ago, so the table stays small.
    def prune(before)
      table = ActiveRecord::Base.connection.quote_table_name('affiliate_rate_counters')
      ActiveRecord::Base.connection.exec_delete(
        ActiveRecord::Base.sanitize_sql_array(["DELETE FROM #{table} WHERE window_started_at < ?", before])
      )
    end
  end
end
