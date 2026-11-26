module Affiliates
  # Attaches an affiliate account to an incomplete order (last click within the cookie window).
  # Within the attributing account's cookie_days, an order keeps its first code and a later code
  # is ignored. Once that window has passed, the next code (the same one or another) replaces it.
  # The affiliate's own orders (same user, or the same email on a guest order) are never attributed.
  module Attribution
    module_function

    # true when the order is now attributed to `account` (just now or before), false otherwise.
    def attach(order, account, now: Time.current)
      current_id = order.affiliate_account_id
      if current_id.present? && !expired?(order, now: now)
        return current_id == account.id
      end
      return false if self_referral?(order, account)

      scope = Spree::Order.where(id: order.id, completed_at: nil)
      scope = if current_id.present?
                scope.where(affiliate_account_id: current_id)
                     .where('affiliate_attributed_at IS NULL OR affiliate_attributed_at < ?', window_start(current_id, now))
              else
                scope.where(affiliate_account_id: nil)
              end
      updated = scope.update_all(affiliate_account_id: account.id, affiliate_attributed_at: now, updated_at: now)
      order.reload
      updated == 1 || (order.affiliate_account_id == account.id && !expired?(order, now: now))
    end

    # Whether the order's attribution is older than its account's cookie window, measured at `now`.
    def expired?(order, now: Time.current)
      return false if order.affiliate_account_id.nil?
      return true if order.affiliate_attributed_at.nil?

      order.affiliate_attributed_at < window_start(order.affiliate_account_id, now)
    end

    def window_start(account_id, now)
      days = AffiliateAccount.where(id: account_id).pick(:cookie_days) || Affiliates.config.cookie_days
      now - days.days
    end

    def self_referral?(order, account)
      return true if order.user_id.present? && order.user_id == account.user_id

      email = account.user&.email.to_s
      order.email.present? && email.present? && order.email.to_s.strip.casecmp?(email)
    end
  end
end
