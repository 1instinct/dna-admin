# Feedback sent from a client app: a bug report, an idea, something else, or a 1-5 rating after a
# moment the app chose. Signed-in senders are linked by user; anonymous ones carry the app's
# install id. Settings live on AppFeedback.config (app/services/app_feedback/settings.rb).
class AppFeedback < ApplicationRecord
  KINDS = %w[bug idea other rating].freeze
  STATUSES = %w[new triaged done archived].freeze
  MESSAGE_MAX = 2000
  DIAGNOSTICS_MAX_BYTES = 64.kilobytes
  SCREENSHOT_MAX_BYTES = 5.megabytes
  SCREENSHOT_CONTENT_TYPES = %w[image/jpeg image/png].freeze
  # Short device and build strings.
  SHORT_FIELDS = %i[install_id moment platform os_version device_model app_version build_number channel locale
                    sentry_event_id].freeze
  SHORT_MAX = 128
  EMAIL_MAX = 254

  belongs_to :user, class_name: 'Spree::User', optional: true
  has_one_attached :screenshot

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 },
                     allow_nil: true
  validates :rating, presence: true, if: -> { kind == 'rating' }
  validates :message, presence: true, unless: -> { kind == 'rating' }
  validates :message, length: { maximum: MESSAGE_MAX }
  # On create only: a user deleted later nulls user_id, and the row must stay triageable.
  validates :install_id, presence: true, unless: :user_id, on: :create
  validates(*SHORT_FIELDS, length: { maximum: SHORT_MAX })
  validates :email, length: { maximum: EMAIL_MAX },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'is not a valid email' }, allow_blank: true
  validate :diagnostics_shape_and_size
  validate :screenshot_type_and_size
  validate :text_without_null_bytes

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :with_screenshot, -> { joins(:screenshot_attachment) }
  scope :without_screenshot, -> { where.not(id: ActiveStorage::Attachment.where(record_type: name, name: 'screenshot').select(:record_id)) }

  def self.config
    @config ||= AppFeedback::Settings.new
  end

  # Tests use this to drop overrides.
  def self.reset_config!
    @config = nil
  end

  # The size the diagnostics take as compact JSON, in bytes.
  def diagnostics_bytes
    diagnostics.nil? ? 0 : JSON.generate(diagnostics).bytesize
  end

  # The "Open in Sentry" link, or nil without a sentry_event_id or a configured template.
  def sentry_url
    template = AppFeedback.config.sentry_url_template
    return if template.blank? || sentry_event_id.blank?

    template.gsub('%{id}', ERB::Util.url_encode(sentry_event_id))
  end

  def sender_label
    return "user #{user_id}" if user_id

    "install #{install_id}"
  end

  private

  def diagnostics_shape_and_size
    return if diagnostics.nil?
    return errors.add(:diagnostics, 'must be a JSON object') unless diagnostics.is_a?(Hash)
    # Postgres jsonb refuses \u0000 anywhere in the document.
    return errors.add(:diagnostics, 'contains invalid characters') if JSON.generate(diagnostics).include?('\u0000')
    return if diagnostics_bytes <= DIAGNOSTICS_MAX_BYTES

    errors.add(:diagnostics, "must be at most #{DIAGNOSTICS_MAX_BYTES / 1.kilobyte} KB")
  end

  def screenshot_type_and_size
    return unless screenshot.attached?

    blob = screenshot.blob
    errors.add(:screenshot, 'must be a JPEG or PNG image') unless SCREENSHOT_CONTENT_TYPES.include?(blob.content_type)
    return if blob.byte_size <= SCREENSHOT_MAX_BYTES

    errors.add(:screenshot, "must be at most #{SCREENSHOT_MAX_BYTES / 1.megabyte} MB")
  end

  def text_without_null_bytes
    ([:message, :email, :admin_note] + SHORT_FIELDS).each do |field|
      value = self[field]
      errors.add(field, 'contains invalid characters') if value.is_a?(String) && value.include?("\0")
    end
  end
end
