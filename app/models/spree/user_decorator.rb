Spree::User.class_eval do
  enum consultation_status: {
    none: 0,
    pending: 1,
    pass: 2,
    fail: 3
  }, _prefix: :consultation

  def consultation_passed?
    consultation_pass?
  end

  has_many :sent_messages, class_name: 'Message', as: :sender, dependent: :destroy
  has_many :received_messages, class_name: 'Message', as: :receiver, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorite_variants, through: :favorites, source: :variant

  has_many :follower_relationships, class_name: 'UserFollow', foreign_key: :following_id, dependent: :destroy
  has_many :followers, through: :follower_relationships, source: :follower
  has_many :following_relationships, class_name: 'UserFollow', foreign_key: :follower_id, dependent: :destroy
  has_many :followings, through: :following_relationships, source: :following
end
