module Reviews
  # Which channel a purchase belongs to. Wholesale when either signal says so:
  #   - the order's channel is "wholesale" (set at completion for wholesale accounts, or by an
  #     admin on a phone, email or invoice order; see Spree::OrderWholesaleChannelDecorator)
  #   - the buyer has the "wholesale" Spree role
  # Everything else is retail.
  module Channel
    module_function

    def for(order: nil, user: nil)
      return 'wholesale' if order&.channel.to_s == 'wholesale'
      return 'wholesale' if wholesale_user?(user || order&.user)

      'retail'
    end

    def wholesale_user?(user)
      user.present? && user.has_spree_role?(WHOLESALE_ROLE)
    end

    # Who may see wholesale reviews (the "all" and "wholesale" scopes): wholesale accounts and
    # admins. Everyone else gets retail reviews only, whatever they ask for.
    def wholesale_viewer?(user)
      user.present? && (wholesale_user?(user) || user.has_spree_role?('admin'))
    end

    # The review scope a request may read: the asked-for one when allowed, else retail.
    def allowed_scope(requested, viewer)
      scope = requested.to_s
      return 'retail' unless Spree::ReviewStat::SCOPES.include?(scope)
      return scope if scope == 'retail' || wholesale_viewer?(viewer)

      raise Reviews::Error.new(:forbidden, 'Wholesale reviews are only available to wholesale accounts')
    end
  end
end
