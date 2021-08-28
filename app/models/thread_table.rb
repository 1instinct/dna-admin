class ThreadTable < Spree::Base
  has_one :live_stream, dependent: :destroy
  has_one :actor, dependent: :destroy
  has_many :messages, dependent: :destroy
  self.whitelisted_ransackable_attributes = %w[id]
end
