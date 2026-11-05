module Iap
  # Manual revocation by an admin, with a required note in the audit log. The
  # revocation sticks: later store data for the same transaction does not
  # restore access.
  class AdminRevocation
    def initialize(transaction, admin:, note:)
      @transaction = transaction
      @admin = admin
      @note = note.to_s.strip
    end

    def call
      raise ArgumentError, 'a note is required' if @note.empty?

      Spree::IapTransaction.transaction do
        @transaction.update!(status: 'revoked', admin_revoked_at: Time.current)
        Spree::IapAuditLog.create!(iap_transaction: @transaction, admin_user: @admin, action: 'revoke', note: @note)
      end
      EntitlementResolver.refresh(@transaction.user) if @transaction.user
      @transaction
    end
  end
end
