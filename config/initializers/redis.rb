# redis-rb 5.x removed Redis.current — use a global constant instead
REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
