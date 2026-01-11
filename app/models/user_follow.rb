class UserFollow < Spree::Base
  belongs_to :follower, class_name: 'Spree::User'
  belongs_to :following, class_name: 'Spree::User'
  
  validates :follower_id, presence: true
  validates :following_id, presence: true
  validates :follower_id, uniqueness: { scope: :following_id, message: "already following this user" }
  validate :cannot_follow_self
  
  # Ransackable attributes for search
  self.whitelisted_ransackable_attributes = %w[follower_id following_id created_at]
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_follower, ->(user) { where(follower: user) }
  scope :for_following, ->(user) { where(following: user) }
  
  # Check if user is following another user
  def self.following?(follower, following)
    exists?(follower: follower, following: following)
  end
  
  # Toggle follow (add if not exists, remove if exists)
  def self.toggle(follower, following)
    follow = find_by(follower: follower, following: following)
    if follow
      follow.destroy
      false
    else
      new_follow = new(follower: follower, following: following)
      new_follow.save
    end
  end
  
  private
  
  def cannot_follow_self
    if follower_id == following_id
      errors.add(:following_id, "cannot follow yourself")
    end
  end
end
