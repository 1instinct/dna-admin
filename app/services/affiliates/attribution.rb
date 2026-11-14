module Affiliates
  # Attaches an affiliate account to an incomplete order. An order is attributed at most once: a
  # later code is ignored. The affiliate's own orders (same user, or the same email on a guest
  # order) are never attributed.
  module Attribution
    module_function

    # true when the order is now attributed to `account` (just now or before), false otherwise.
    def attach(order, account, now: Time.current)
      return order.affiliate_account_id == account.id if order.affiliate_account_id.present?
      return false if self_referral?(order, account)

      updated = Spree::Order.where(id: order.id, affiliate_account_id: nil, completed_at: nil)
                            .update_all(affiliate_account_id: account.id, affiliate_attributed_at: now, updated_at: now)
      order.reload
      updated == 1 || order.affiliate_account_id == account.id
    end

    def self_referral?(order, account)
      return true if order.user_id.present? && order.user_id == account.user_id

      email = account.user&.email.to_s
      order.email.present? && email.present? && order.email.to_s.strip.casecmp?(email)
    end
  end
end
