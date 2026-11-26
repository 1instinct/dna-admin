module Reviews
  # Loyalty points for a published product review: points_per_review, plus points_photo_bonus when
  # it has photos (settings). Paid once per review, the first time it's published, to a signed-in
  # reviewer, whatever the rating (FTC 16 CFR 465.4: an incentive may not depend on sentiment).
  # Store reviews earn nothing. Reviews that earn points are flagged incentivized when submitted,
  # so the page and Google's feed can say so.
  module AwardPoints
    module_function

    def call(review, settings: Spree::ReviewSetting.current, now: Time.current)
      return unless eligible?(review, settings)

      review.with_lock do
        next if review.points_awarded_at.present?

        points = points_for(review, settings)
        Spree::LoyaltyPointsCreditTransaction.create!(
          user: review.user, source: review, loyalty_points: points,
          comment: "Review of #{review.reviewable.try(:name)}".truncate(255)
        )
        review.update_columns(points_awarded_at: now, updated_at: now)
        points
      end
    end

    def eligible?(review, settings)
      review.published? && review.points_awarded_at.nil? && review.user.present? && !review.user.deleted? &&
        review.reviewable_type == Spree::Product.name && settings.points_per_review.positive?
    end

    def points_for(review, settings)
      settings.points_per_review + (review.photos.attached? ? settings.points_photo_bonus : 0)
    end

    # Whether submitting this review now would earn points; recorded as Review#incentivized.
    def offered?(user, reviewable, settings: Spree::ReviewSetting.current)
      user.present? && reviewable.is_a?(Spree::Product) && settings.points_per_review.positive?
    end
  end
end
