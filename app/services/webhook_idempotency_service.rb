class WebhookIdempotencyService
  TTL = 86_400 # 24 hours

  def self.already_processed?(source, event_id)
    key = "webhook:#{source}:#{event_id}"
    !REDIS.set(key, "1", nx: true, ex: TTL)
  end

  def self.clear!(source, event_id)
    key = "webhook:#{source}:#{event_id}"
    REDIS.del(key)
  end
end
