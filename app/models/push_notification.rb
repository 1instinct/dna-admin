class PushNotification < ApplicationRecord
  # Raised by deliver! when the notification can't be sent as it is.
  class NotSendable < StandardError; end

  # What a sent notification records; it isn't changed afterwards.
  CONTENT_FIELDS = %w[title body notification_type data target target_user_id].freeze

  belongs_to :sent_by, class_name: 'Spree::User', optional: true

  validates :title, presence: true
  validates :body, presence: true
  validates :notification_type, inclusion: { in: %w[custom product order promo] }
  validates :target, inclusion: { in: %w[all segment user] }
  validates :status, inclusion: { in: %w[draft sent failed] }
  validate :content_unchanged_once_sent, on: :update

  # Only drafts (made from the mobile admin app) can be deleted; sent ones are the send history.
  before_destroy :only_drafts_deleted

  scope :recent, -> { order(created_at: :desc) }
  scope :sent, -> { where(status: 'sent') }

  def draft?
    status == 'draft'
  end

  # Sends a draft through ExpoPushService, as the admin's Send form does, and records the outcome
  # on it: sent and error counts, the error log, the status (failed when nothing went out) and who
  # sent it. A notification is sent at most once.
  def deliver!(sent_by: nil)
    with_lock do
      raise NotSendable, 'Only a draft can be sent.' unless draft?

      validate!
      payload = (data.is_a?(Hash) ? data : {}).merge('type' => notification_type)
      results =
        case target
        when 'all'
          ExpoPushService.send_to_all(title: title, body: body, data: payload)
        when 'user'
          raise NotSendable, 'Choose the user to send it to.' if target_user_id.blank?

          ExpoPushService.send_to_user(user_id: target_user_id, title: title, body: body, data: payload)
        else
          raise NotSendable, "Sending to a #{target} isn't supported."
        end
      update!(data: payload, sent_count: results[:sent], error_count: results[:errors].size,
              errors_log: results[:errors].any? ? results[:errors].join("\n") : nil,
              status: results[:errors].any? && results[:sent].zero? ? 'failed' : 'sent', sent_by: sent_by)
    end
    self
  end

  def target_description
    case target
    when 'all' then 'All devices'
    when 'user' then "User ##{target_user_id}"
    when 'segment' then data&.dig('segment') || 'Segment'
    end
  end

  private

  def content_unchanged_once_sent
    return if status_in_database == 'draft'
    return if (changed & CONTENT_FIELDS).empty?

    errors.add(:base, "A notification that was sent can't be changed.")
  end

  def only_drafts_deleted
    return if status_in_database == 'draft'

    errors.add(:base, "A notification that was sent can't be deleted.")
    throw :abort
  end
end
