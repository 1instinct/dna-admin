module DigitalAssets
  # Per-user fixed-window limits on the counter table Profiles::RateLimit keeps (one atomic upsert
  # per hit). Fails open: a counter error never takes the endpoint down.
  #
  #   DigitalAssets::RateLimit.allow?(user, :library_links, { limit: 60, window: 1.minute })
  module RateLimit
    module_function

    def allow?(user, action, rule, now: Time.current)
      return true unless user&.persisted? && rule

      Profiles::RateLimit.hit(user.id, action, rule[:window], now) <= rule[:limit]
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[digital_assets] rate limit check failed: #{e.class}")
      true
    end
  end
end
