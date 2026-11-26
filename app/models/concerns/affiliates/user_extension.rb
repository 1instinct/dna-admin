module Affiliates
  # The user's affiliate account, if they applied.
  module UserExtension
    extend ActiveSupport::Concern

    included do
      has_one :affiliate_account, class_name: 'AffiliateAccount', foreign_key: :user_id, inverse_of: :user
    end
  end
end
