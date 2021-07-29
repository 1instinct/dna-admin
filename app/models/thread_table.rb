class ThreadTable < Spree::Base
  has_many :live_streams, dependent: :destroy
  has_many :messages, dependent: :destroy
  self.whitelisted_ransackable_attributes = %w[id]
end
