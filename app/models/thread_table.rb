# A message thread. One with a contact is a customer conversation (Chat::Conversations): open,
# snoozed or closed, on a channel (web, email, ...), with unread counters for each side. Threads
# without a contact (live stream chats, older two-party threads) work as before.
class ThreadTable < Spree::Base
  STATUSES = %w[open snoozed closed].freeze
  SUBJECT_MAX = 255

  has_one :live_stream, dependent: :destroy
  has_one :actor, dependent: :destroy
  has_many :live_streams, dependent: :destroy
  has_many :messages, dependent: :destroy
  belongs_to :contact, optional: true
  belongs_to :assignee, class_name: 'Spree::User', optional: true
  belongs_to :visitor_session, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :subject, length: { maximum: SUBJECT_MAX }
  validates :staff_unread_count, :customer_unread_count, numericality: { greater_than_or_equal_to: 0 }

  scope :conversations, -> { where.not(contact_id: nil) }
  scope :not_closed, -> { where.not(status: 'closed') }
  scope :recent_activity_first, -> { order(Arel.sql('thread_tables.last_message_at DESC NULLS LAST, thread_tables.id DESC')) }

  self.whitelisted_ransackable_attributes = %w[id]

  def conversation?
    contact_id.present?
  end

  def open?
    status == 'open'
  end

  def closed?
    status == 'closed'
  end

  # The last message the customer can see (not a note).
  def last_visible_message
    messages.visible_to_customer.reorder(id: :desc).first
  end
end
