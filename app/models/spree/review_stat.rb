# Rating aggregates for one product or the store, per scope:
#   retail     retail reviews only; what every public page shows
#   wholesale  wholesale reviews only; the "Wholesale only" filter
#   all        both; the default on wholesale product pages
# Rebuilt by Reviews::RefreshStats whenever a review is published, unpublished, edited or moves
# channel. The AI summary is written to the retail row only.
module Spree
  class ReviewStat < Spree::Base
    self.table_name = 'spree_review_stats'

    SCOPES = %w[retail wholesale all].freeze

    belongs_to :reviewable, polymorphic: true

    validates :scope, inclusion: { in: SCOPES }, uniqueness: { scope: %i[reviewable_type reviewable_id] }

    def self.for(reviewable, scope)
      find_by(reviewable_type: reviewable.class.base_class.name, reviewable_id: reviewable.id, scope: scope.to_s) ||
        new(reviewable: reviewable, scope: scope.to_s)
    end

    def histogram_counts
      (1..5).index_with { |n| histogram.fetch(n.to_s, 0).to_i }
    end

    def visible_ai_summary
      ai_summary if ai_summary.present? && !ai_summary_hidden
    end
  end
end
