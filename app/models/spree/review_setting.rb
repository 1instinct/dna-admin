# Review settings, one row (singleton_guard is always 0 and unique). Edited in Spree admin under
# Reviews > Settings. Read through ReviewSetting.current, which returns unsaved defaults while the
# table is missing (deployed, not yet migrated), so callers never need a nil check.
module Spree
  class ReviewSetting < Spree::Base
    self.table_name = 'spree_review_settings'

    DAY_FIELDS = %i[request_delay_days international_request_delay_days reminder_delay_days request_expiry_days].freeze
    POINT_FIELDS = %i[points_per_review points_photo_bonus].freeze

    validates(*DAY_FIELDS, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 })
    validates(*POINT_FIELDS, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 })
    validates :ai_summary_min_reviews, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

    before_validation -> { self.singleton_guard = 0 }

    def self.current
      return new unless table_exists?

      first || create!
    rescue ActiveRecord::RecordNotUnique
      first
    end
  end
end
