module Chat
  # Fixed-window counters for the storefront chat and visit API, in Rails.cache (this app has no
  # Rack::Attack). Rules are Chat.config.rate_limits; keys are a visitor token or an IP, stored
  # only as an HMAC.
  #
  #   Chat::RateLimit.allow?(:message, token) # counts this attempt; false once over the limit
  #
  # Limits hold across processes only when Rails.cache is shared (Memcached, Redis); with a file or
  # memory store each process counts on its own. A NullStore (caching off) is swapped for a
  # process-local memory store so limits still apply. Fails open on a cache error.
  module RateLimit
    module_function

    def allow?(rule_name, key, now: Time.current)
      return true if key.blank?

      rule = Chat.config.rate_limits.fetch(rule_name)
      hit(rule_name, key, rule[:window], now) <= rule[:limit]
    rescue StandardError => e
      raise if e.is_a?(KeyError)

      Rails.logger.error("[chat] rate limit check failed: #{e.class}")
      true
    end

    # Seconds until the rule's current window ends, for a 429's Retry-After.
    def retry_after(rule_name, now: Time.current)
      window = Chat.config.rate_limits.fetch(rule_name)[:window].to_i
      [window - (now.to_i % window), 1].max
    end

    # Hits so far in the current window, without counting one.
    def count(rule_name, key, now: Time.current)
      rule = Chat.config.rate_limits.fetch(rule_name)
      store.read(cache_key(rule_name, key, rule[:window], now), raw: true).to_i
    end

    def hit(rule_name, key, window, now)
      cache_key = cache_key(rule_name, key, window, now)
      count = store.increment(cache_key, 1, expires_in: window + 1.minute)
      return count.to_i if count

      # Stores that don't create a missing key on increment (memory, file).
      store.write(cache_key, 1, expires_in: window + 1.minute, raw: true)
      1
    end

    def cache_key(rule_name, key, window, now)
      bucket = now.to_i / window.to_i
      digest = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base.to_s, "chat-rate:#{key}")
      "chat:rate:#{rule_name}:#{digest}:#{bucket}"
    end

    def store
      configured = Chat.config.rate_limit_store
      return configured if configured
      return Rails.cache unless Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

      @fallback_store ||= ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
    end
  end
end
