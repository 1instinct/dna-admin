module Reviews
  # "Was this review helpful?" One vote per voter per review; voting again changes or (with the
  # same answer) keeps the vote. Counters on the review are recounted from the votes, so they
  # can't drift.
  module Votes
    module_function

    def cast(review, helpful:, user: nil, visitor_id: nil)
      key = Spree::ReviewVote.key_for(user: user, visitor_id: visitor_id)
      raise Reviews::Error.new(:invalid, 'A visitor id is required to vote') if key.nil?
      raise Reviews::Error, :not_found unless review.published?

      vote = Spree::ReviewVote.find_or_initialize_by(review: review, voter_key: key)
      vote.assign_attributes(helpful: ActiveModel::Type::Boolean.new.cast(helpful), user: user)
      vote.save!
      recount([review.id])
      review.reload
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def recount(review_ids)
      return if review_ids.blank?

      table = Spree::Review.quoted_table_name
      votes = Spree::ReviewVote.quoted_table_name
      Spree::Review.where(id: review_ids).update_all(<<~SQL.squish)
        helpful_count = (SELECT COUNT(*) FROM #{votes} v WHERE v.review_id = #{table}.id AND v.helpful),
        unhelpful_count = (SELECT COUNT(*) FROM #{votes} v WHERE v.review_id = #{table}.id AND NOT v.helpful)
      SQL
    end
  end
end
