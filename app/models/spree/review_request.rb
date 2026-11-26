# The post-purchase "How's your order?" email for one order. Created when the order ships
# (ReviewRequests::Schedule) and moved along by `rake reviews:dispatch`; all state lives here, so
# the task can run hourly, twice, or after a restart without sending anything twice.
#
# The email link carries a random token; only its SHA256 is stored. The token proves the
# purchase, so a guest checkout can review without an account.
module Spree
  class ReviewRequest < Spree::Base
    self.table_name = 'spree_review_requests'

    STATUSES = %w[scheduled sent reminded completed opted_out expired cancelled].freeze
    OPEN_STATUSES = %w[sent reminded].freeze

    belongs_to :order, class_name: 'Spree::Order'
    belongs_to :user, class_name: 'Spree::User', optional: true
    has_many :reviews, class_name: 'Spree::Review', dependent: :nullify

    validates :order_id, uniqueness: true
    validates :email, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :send_after, presence: true

    scope :due, ->(now = Time.current) { where(status: 'scheduled').where('send_after <= ?', now) }

    # Statuses whose link still opens the review page (until expires_at): a completed request
    # keeps working so the customer can see and edit what they sent.
    LINK_STATUSES = (OPEN_STATUSES + %w[completed]).freeze

    def self.digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    # The open request for a link's token, or nil (unknown, expired, opted out, completed).
    def self.find_by_token(token)
      return if token.blank?

      request = find_by(token_digest: digest(token))
      request if request&.open?
    end

    # The request behind a review page link: open, or completed and not yet expired. Nil for an
    # unknown, expired, opted-out or cancelled link.
    def self.find_for_link(token, now = Time.current)
      return if token.blank?

      request = find_by(token_digest: digest(token))
      request if request&.link_usable?(now)
    end

    # Whether this address asked for no more review emails (the opt-out link of any request).
    def self.opted_out?(email)
      email.present? && where('LOWER(email) = ?', email.to_s.strip.downcase).where(status: 'opted_out').exists?
    end

    # A fresh token for an email; replaces the previous one, so only the latest link works.
    def issue_token!
      token = SecureRandom.urlsafe_base64(32)
      update!(token_digest: self.class.digest(token))
      token
    end

    def open?(now = Time.current)
      OPEN_STATUSES.include?(status) && (expires_at.nil? || expires_at > now)
    end

    def link_usable?(now = Time.current)
      LINK_STATUSES.include?(status) && (expires_at.nil? || expires_at > now)
    end

    # The order's reviewable items (Reviews::Eligibility), each with the customer's review if any.
    def items
      Reviews::Eligibility.for_order(order)
    end

    # Every reviewable item has a review. False when there is nothing to review.
    def all_reviewed?(list = items)
      list.any? && list.all?(&:existing_review)
    end

    # Marks the request completed once every item is reviewed. Returns true when it did.
    def complete_if_reviewed!(now = Time.current)
      return false unless OPEN_STATUSES.include?(status) && all_reviewed?

      update!(status: 'completed', completed_at: now)
      true
    end
  end
end
