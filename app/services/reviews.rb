# Product and store reviews. Design: docs/plans/2026-11-26-product-reviews-design.md.
#
#   Reviews::Channel       retail or wholesale, from the order and the buyer's role
#   Reviews::Eligibility   what a customer (or an order's review link) may review
#   Reviews::Submit        create or edit a review, then run it through moderation
#   Reviews::Moderation    publish, hold, reject, hide; never reads the rating
#   Reviews::RefreshStats  per-channel rating aggregates on Spree::ReviewStat and the product
#   Reviews::AwardPoints   loyalty points for a published product review, once
#   Reviews::Anonymize     what account deletion does to a user's reviews, votes and questions
#
# Settings live on Spree::ReviewSetting.current (admin: Reviews > Settings).
module Reviews
  WHOLESALE_ROLE = 'wholesale'.freeze

  # Links, email addresses and phone numbers hold a review for a person to check.
  CONTACT_PATTERN = %r{
    https?://|www\.|\b[a-z0-9-]+\.(?:com|net|org|io|co|shop|store|biz|info|link|ly)\b|
    [\w.+-]+@[\w-]+\.[\w.]+|
    (?:\+?\d[\s().-]?){9,}
  }xi.freeze

  # Raised by services for a request the caller should refuse (not found, not allowed).
  class Error < StandardError
    attr_reader :code

    def initialize(code, message = nil)
      @code = code
      super(message || code.to_s.humanize)
    end
  end
end
