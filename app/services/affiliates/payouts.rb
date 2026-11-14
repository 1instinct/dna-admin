module Affiliates
  # Records a manual payout: every approved commission of the account in one currency is marked
  # paid and linked to a new AffiliatePayout for their sum.
  module Payouts
    class Error < StandardError; end

    module_function

    def create!(account:, reference:, note: nil, currency: nil, now: Time.current)
      reference = reference.to_s.strip
      raise Error, 'A payment reference is required' if reference.empty?

      AffiliateCommission.sweep!(now: now)
      currency = currency.presence || account.currency

      AffiliatePayout.transaction do
        account.lock!
        commissions = account.commissions.approved.where(currency: currency).lock.to_a
        raise Error, 'There are no approved commissions to pay' if commissions.empty?

        payout = AffiliatePayout.create!(affiliate_account: account, amount: commissions.sum(&:amount), currency: currency,
                                         reference: reference, note: note.to_s.strip.presence, paid_at: now)
        AffiliateCommission.where(id: commissions.map(&:id))
                           .update_all(state: 'paid', affiliate_payout_id: payout.id, updated_at: now)
        payout
      end
    end

    # { currency => amount } of approved, unpaid commissions for the account.
    def payable(account)
      account.commissions.approved.group(:currency).sum(:amount)
    end
  end
end
