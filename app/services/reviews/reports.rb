module Reviews
  # Customer reports on reviews (Spree::ContentReport with a review as reportable). The review's
  # reports_count tracks its open reports; at Spree::ContentReport::REVIEW_HOLD_THRESHOLD a
  # published review goes back to the moderation queue (held as "reported") until an admin
  # publishes it again. Reports are about content, not ratings, so this applies equally to every
  # star level.
  module Reports
    module_function

    def after_report(review)
      count = refresh_count(review)
      return unless review.published? && count >= Spree::ContentReport::REVIEW_HOLD_THRESHOLD

      Reviews::Moderation.hold!(review, 'reported')
    end

    def refresh_count(review)
      count = Spree::ContentReport.about_review(review).where(status: 'open').count
      review.update_columns(reports_count: count, updated_at: Time.current)
      count
    end
  end
end
