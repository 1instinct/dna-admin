module Spree
  # blocker blocks blocked. While a block exists either way, neither sees the other's profile,
  # neither can follow or report the other, and creating it removes follows both ways.
  class UserBlock < Spree::Base
    self.table_name = 'spree_user_blocks'

    belongs_to :blocker, class_name: 'Spree::User'
    belongs_to :blocked, class_name: 'Spree::User'

    validates :blocked_id, uniqueness: { scope: :blocker_id }
    validate :not_self

    after_create :remove_follows

    def self.between?(a, b)
      return false unless a&.id && b&.id

      where(blocker_id: a.id, blocked_id: b.id).or(where(blocker_id: b.id, blocked_id: a.id)).exists?
    end

    def self.involving(user)
      where(blocker_id: user.id).or(where(blocked_id: user.id))
    end

    # Idempotent: returns the existing block when there is one.
    def self.block!(blocker, blocked)
      find_by(blocker_id: blocker.id, blocked_id: blocked.id) || create!(blocker: blocker, blocked: blocked)
    rescue ActiveRecord::RecordNotUnique
      find_by!(blocker_id: blocker.id, blocked_id: blocked.id)
    end

    private

    def not_self
      errors.add(:blocked, "can't be yourself") if blocker_id.present? && blocker_id == blocked_id
    end

    def remove_follows
      UserFollow.where(follower_id: blocker_id, following_id: blocked_id)
                .or(UserFollow.where(follower_id: blocked_id, following_id: blocker_id))
                .delete_all
    end
  end
end
