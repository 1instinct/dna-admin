class AppFeedback < ApplicationRecord
  # One row per rate-limited key; see AppFeedback::RateLimit.
  class RateCounter < ApplicationRecord
    self.table_name = 'app_feedback_rate_counters'
  end
end
