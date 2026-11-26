# One "was this helpful?" vote per voter per review. voter_key is a SHA256 of "user:<id>" for
# signed-in voters or of the storefront's anonymous visitor id, so the same person voting twice
# changes their vote instead of adding one. The review's helpful/unhelpful counters are kept in
# step by Reviews::Vote.
module Spree
  class ReviewVote < Spree::Base
    self.table_name = 'spree_review_votes'

    belongs_to :review, class_name: 'Spree::Review'
    belongs_to :user, class_name: 'Spree::User', optional: true

    validates :voter_key, presence: true, uniqueness: { scope: :review_id }
    validates :helpful, inclusion: { in: [true, false] }

    def self.key_for(user: nil, visitor_id: nil)
      raw = user ? "user:#{user.id}" : "visitor:#{visitor_id}"
      return if user.nil? && visitor_id.blank?

      Digest::SHA256.hexdigest(raw)
    end
  end
end
