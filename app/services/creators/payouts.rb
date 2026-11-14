module Creators
  # Creator payouts. Money moves outside the app; recording a payout (with the payment's
  # reference) marks the account's payable earnings in that currency paid.
  module Payouts
    class Error < StandardError; end

    module_function

    # { currency => payable amount } for the account (after a sweep).
    def payable(account)
      Spree::CreatorEarning.sweep!
      Spree::CreatorEarning.payable.where(creator_account_id: account.id).group(:currency).sum(:amount)
    end

    def create!(account:, reference:, currency:, note: nil, now: Time.current)
      reference = reference.to_s.strip
      raise Error, 'A payment reference is required' if reference.empty?

      Spree::CreatorEarning.sweep!(now: now)
      Spree::CreatorPayout.transaction do
        Spree::CreatorAccount.where(id: account.id).lock.pluck(:id)
        # Lock and fix the payable rows once; the total and the update use exactly these ids, so an
        # earning voided or made payable meanwhile is neither paid without being counted nor counted
        # without being paid.
        ids = Spree::CreatorEarning.payable.where(creator_account_id: account.id, currency: currency.to_s)
                                   .order(:id).lock.pluck(:id)
        earnings = Spree::CreatorEarning.where(id: ids)
        total = earnings.sum(:amount)
        raise Error, "Nothing is payable in #{currency}" unless total.positive?

        payout = Spree::CreatorPayout.create!(creator_account: account, amount: total, currency: currency.to_s,
                                              reference: reference, note: note.to_s.strip.presence, paid_at: now)
        earnings.update_all(state: 'paid', creator_payout_id: payout.id, updated_at: now)
        payout
      end
    end
  end
end
