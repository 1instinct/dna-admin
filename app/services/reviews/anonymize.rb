module Reviews
  # What account deletion (AccountDeletion) does to a user's review content:
  #   reviews     kept, with no user and the name "Former customer"; photos purged after commit
  #               (they may show the person). Rating and text stay, so averages don't move.
  #   questions,  kept the same way, as "Former customer".
  #   answers
  #   votes       deleted; the affected reviews' helpful counts are recounted.
  #   requests    review emails not yet sent or still open are cancelled; the email address and
  #               link are cleared.
  module Anonymize
    module_function

    # Inside AccountDeletion's transaction. Returns the photo blobs to purge after commit.
    def call(user, now: Time.current)
      blobs = []
      reviewables = []
      Spree::Review.where(user_id: user.id).includes(photos_attachments: :blob).find_each do |review|
        blobs.concat(review.photos.map(&:blob))
        review.photos.each(&:delete) if review.photos.attached?
        reviewables << [review.reviewable_type, review.reviewable_id] if review.published?
      end
      Spree::Review.where(user_id: user.id).update_all(user_id: nil, display_name: Spree::Review::ANONYMOUS_NAME,
                                                       ip_hash: nil, updated_at: now)
      Spree::ProductQuestion.where(user_id: user.id).update_all(user_id: nil, display_name: Spree::Review::ANONYMOUS_NAME,
                                                                updated_at: now)
      Spree::ProductAnswer.where(user_id: user.id).update_all(user_id: nil, display_name: Spree::Review::ANONYMOUS_NAME,
                                                              updated_at: now)
      remove_votes(user)
      cancel_requests(user, now)
      refresh(reviewables.uniq)
      blobs
    end

    def remove_votes(user)
      review_ids = Spree::ReviewVote.where(user_id: user.id).distinct.pluck(:review_id)
      Spree::ReviewVote.where(user_id: user.id).delete_all
      Reviews::Votes.recount(review_ids)
    end

    def cancel_requests(user, now)
      requests = Spree::ReviewRequest.where(user_id: user.id)
      requests.where(status: %w[scheduled sent reminded]).update_all(status: 'cancelled', updated_at: now)
      requests.update_all(user_id: nil, email: 'deleted@invalid', token_digest: nil, updated_at: now)
    end

    # Photo counts change when photos go; ratings don't.
    def refresh(reviewables)
      reviewables.each do |type, id|
        reviewable = type.constantize.unscoped { type.constantize.find_by(id: id) }
        Reviews::RefreshStats.call(reviewable) if reviewable
      end
    end
  end
end
