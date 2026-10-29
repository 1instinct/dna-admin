module Iap
  # Fixed-window counter on Rails.cache (falls back to an in-process store
  # when the app cache is a null store). Use a shared cache (Redis/Memcached)
  # in production for limits across dynos.
  class RateLimiter
    class << self
      attr_writer :store

      def store
        @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
      end

      # true when the call is allowed
      def allow?(key, limit:, period:)
        window = Time.now.to_i / period.to_i
        cache_key = "iap:rate:#{key}:#{window}"
        count = store.increment(cache_key, 1, expires_in: period * 2)
        if count.nil?
          store.write(cache_key, 1, expires_in: period * 2, raw: true)
          count = 1
        end
        count <= limit
      end
    end
  end
end
