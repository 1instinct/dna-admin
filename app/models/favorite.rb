class Favorite < Spree::Base
  belongs_to :user, class_name: 'Spree::User'
  belongs_to :variant, class_name: 'Spree::Variant'
  
  has_one :product, through: :variant
  
  validates :user_id, uniqueness: { scope: :variant_id, message: "has already favorited this variant" }
  
  # Ransackable attributes for search
  self.whitelisted_ransackable_attributes = %w[user_id variant_id created_at is_public]
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_variant, ->(variant) { where(variant: variant) }
  scope :public_favorites, -> { where(is_public: true) }
  
  # Check if user has favorited a variant
  def self.favorited?(user, variant)
    exists?(user: user, variant: variant)
  end
  
  # Toggle favorite (add if not exists, remove if exists)
  def self.toggle(user, variant)
    favorite = find_by(user: user, variant: variant)
    if favorite
      favorite.destroy
      false
    else
      create(user: user, variant: variant)
      true
    end
  end
end
