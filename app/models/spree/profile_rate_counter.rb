module Spree
  # One row per user and limited action; see Profiles::RateLimit.
  class ProfileRateCounter < Spree::Base
    self.table_name = 'spree_profile_rate_counters'
  end
end
