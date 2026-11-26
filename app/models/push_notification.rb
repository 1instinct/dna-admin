class PushNotification < ApplicationRecord
  belongs_to :sent_by, class_name: 'Spree::User', optional: true

  validates :title, presence: true
  validates :body, presence: true
  validates :notification_type, inclusion: { in: %w[custom product order promo] }
  validates :target, inclusion: { in: %w[all segment user] }
  validates :status, inclusion: { in: %w[draft sent failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :sent, -> { where(status: 'sent') }

  def target_description
    case target
    when 'all' then 'All devices'
    when 'user' then "User ##{target_user_id}"
    when 'segment' then data&.dig('segment') || 'Segment'
    end
  end
end
