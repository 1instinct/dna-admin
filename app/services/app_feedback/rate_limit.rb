class AppFeedback < ApplicationRecord
  # Counts feedback per sender (user or install) and per IP, in the fixed windows of
  # AppFeedback.config.rate_limits. Same design as Profiles::RateLimit: one atomic upsert per
  # check in Postgres, so limits hold across dynos and restarts with no extra service. Keys are
  # strings so anonymous installs and IPs count too; an IP is stored only as an HMAC.
  #
  #   AppFeedback::RateLimit.allow?(:sender, "user:12") # counts this attempt; false once over
  #
  # Fails open: a counter error never loses feedback.
  module RateLimit
    module_function

    def allow?(rule_name, key, now: Time.current)
      return true if key.blank?

      rule = AppFeedback.config.rate_limits.fetch(rule_name)
      hit("#{rule_name}:#{key}", rule[:window], now) <= rule[:limit]
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[feedback] rate limit check failed: #{e.class}")
      true
    end

    # "user:<id>" when signed in, else "install:<install_id>".
    def sender_key(user, install_id)
      return "user:#{user.id}" if user&.persisted?

      "install:#{install_id}" if install_id.present?
    end

    def ip_key(ip)
      return if ip.blank?

      OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base.to_s, "feedback-ip:#{ip}")
    end

    def hit(key, window, now)
      table = AppFeedback::RateCounter.quoted_table_name
      sql = AppFeedback::RateCounter.sanitize_sql_array([<<~SQL, { key: key, now: now, cutoff: now - window }])
        INSERT INTO #{table} (key, window_started_at, hits)
        VALUES (:key, :now, 1)
        ON CONFLICT (key) DO UPDATE SET
          hits = CASE WHEN #{table}.window_started_at <= :cutoff THEN 1 ELSE #{table}.hits + 1 END,
          window_started_at = CASE WHEN #{table}.window_started_at <= :cutoff THEN :now ELSE #{table}.window_started_at END
        RETURNING hits
      SQL
      connection = AppFeedback::RateCounter.connection
      hits = connection.uncached { connection.select_value(sql) }.to_i
      prune(now - (2 * window)) if rand < 0.01
      hits
    end

    # Rows whose window ended long ago carry no information; drop them now and then so anonymous
    # installs and IPs don't pile up.
    def prune(before)
      AppFeedback::RateCounter.where('window_started_at < ?', before).delete_all
    end
  end
end
