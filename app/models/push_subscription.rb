class PushSubscription < ApplicationRecord
  belongs_to :user, class_name: 'Spree::User'

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }

  scope :enabled, -> { where(enabled: true) }
  scope :ios, -> { where(platform: 'ios') }
  scope :android, -> { where(platform: 'android') }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
end
