# A person on the storefront: a visitor the chat widget knows by its visitor_token, a customer who
# wrote in, or both. user_id links the signed-in account; actor_id is the older name for the same
# link and is kept in step with it, so code that reads or writes either one keeps working.
class Contact < Spree::Base
  # The widget makes it (a random string in localStorage) or the server issues one.
  VISITOR_TOKEN_FORMAT = /\A[A-Za-z0-9_-]{20,64}\z/.freeze
  NAME_MAX = 100
  EMAIL_MAX = 254

  has_many :sent_messages, class_name: 'Message',as: :sender, dependent: :destroy
  has_many :received_messages, class_name: 'Message', as: :receiver, dependent: :destroy
  belongs_to :actor, class_name: 'Spree::User', optional: true
  belongs_to :user, class_name: 'Spree::User', optional: true
  has_many :conversations, class_name: 'ThreadTable', dependent: :nullify
  has_many :visitor_sessions, dependent: :destroy

  before_validation :sync_user_and_actor
  # Older pages and the v1 contacts API show full_name.
  before_save { self.full_name = name if full_name.blank? && name.present? }

  validates :visitor_token, uniqueness: true, format: { with: VISITOR_TOKEN_FORMAT }, allow_nil: true
  validates :name, length: { maximum: NAME_MAX }
  validates :email, length: { maximum: EMAIL_MAX },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'is not a valid email' },
                    allow_blank: true, if: :will_save_change_to_email?

  self.whitelisted_ransackable_attributes = %w[id full_name email]
  self.whitelisted_ransackable_scopes = %w[search_contact]
  def self.search_contact(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:email).where("LOWER(#{Contact.table_name}.email) LIKE LOWER(:query) OR LOWER(full_name) LIKE LOWER(:query)", query: "%#{query}%").distinct
    else
      where("LOWER(#{Contact.table_name}.email) LIKE LOWER(:query) OR LOWER(full_name) LIKE LOWER(:query)", query: "%#{query}%")
    end
  end

  def self.generate_visitor_token
    loop do
      token = SecureRandom.urlsafe_base64(24)
      break token unless exists?(visitor_token: token)
    end
  end

  def self.valid_visitor_token?(token)
    token.is_a?(String) && VISITOR_TOKEN_FORMAT.match?(token)
  end

  # The name staff see: the one given in the chat, else the older full_name, else the email.
  def display_name
    name.presence || full_name.presence || email.presence
  end

  # Seen on the storefront within the window (a visit ping or a chat request).
  def online?(within = 5.minutes)
    last_seen_at.present? && last_seen_at > within.ago
  end

  private

  # Whichever of the two was changed wins; a new record takes whichever is set.
  def sync_user_and_actor
    if will_save_change_to_user_id? && !will_save_change_to_actor_id?
      self.actor_id = user_id
    elsif will_save_change_to_actor_id? && !will_save_change_to_user_id?
      self.user_id = actor_id
    elsif new_record?
      self.user_id ||= actor_id
      self.actor_id ||= user_id
    end
  end
end
