class WebhookEvent < ApplicationRecord
  self.implicit_order_column = "created_at"

  enum source: {
    mdi: 0,
    honeybee: 1,
    internal: 2
  }

  validates :event_type, presence: true
  validates :source, presence: true
end
