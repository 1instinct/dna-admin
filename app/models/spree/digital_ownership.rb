# A user's ownership of a digital variant. source says how it came: an order, an in-app purchase,
# an admin grant or a free claim; source_record points at the order (or other record) when there
# is one. Revoking keeps the row (revoked_at, revoke_reason); a user has at most one active row
# per variant (unique partial index), so grant! is idempotent.
module Spree
  class DigitalOwnership < Spree::Base
    SOURCES = %w[order iap grant free].freeze

    self.table_name = 'spree_digital_ownerships'

    belongs_to :user, class_name: Spree.user_class.to_s
    belongs_to :variant, class_name: 'Spree::Variant', inverse_of: :digital_ownerships
    belongs_to :source_record, polymorphic: true, optional: true, foreign_key: :source_id, foreign_type: :source_type

    scope :active, -> { where(revoked_at: nil) }
    scope :revoked, -> { where.not(revoked_at: nil) }

    validates :source, inclusion: { in: SOURCES }
    validates :granted_at, presence: true
    validates :revoke_reason, length: { maximum: 255 }

    before_validation { self.granted_at ||= Time.current }

    # The user's active ownership of the variant, created when there is none. Safe to repeat and
    # to race: an existing active row is returned as it is.
    def self.grant!(user:, variant:, source:, source_record: nil)
      attempts = 0
      begin
        active.find_by(user_id: user.id, variant_id: variant.id) ||
          create!(user: user, variant: variant, source: source.to_s, source_record: source_record,
                  granted_at: Time.current)
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 2
        raise
      end
    end

    def revoke!(reason)
      return self if revoked?

      update!(revoked_at: Time.current, revoke_reason: reason.to_s.presence)
      self
    end

    def active?
      revoked_at.nil?
    end

    def revoked?
      revoked_at.present?
    end
  end
end
