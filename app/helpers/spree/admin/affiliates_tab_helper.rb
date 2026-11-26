module Spree
  module Admin
    # The sidebar's Affiliates tab is selected on this module's pages only, not on the
    # spree_reffiliate gem's /admin/affiliates pages.
    module AffiliatesTabHelper
      def self.affiliates_tab_match_path(admin_path)
        %r{\A#{Regexp.escape(admin_path.to_s.chomp('/'))}/affiliate_(accounts|commissions|payouts)(/|\?|\z)}
      end
    end
  end
end
