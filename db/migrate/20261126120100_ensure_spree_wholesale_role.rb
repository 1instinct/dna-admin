# The "wholesale" Spree role already drives wholesale pricing (cart and product endpoints in the
# 1instinct Spree fork) and the storefront account's is_wholesale flag, but only Spree's sample
# seeds create it. Reviews::Channel needs it to exist everywhere, so admins can grant it.
class EnsureSpreeWholesaleRole < ActiveRecord::Migration[6.1]
  class Role < ActiveRecord::Base
    self.table_name = 'spree_roles'
  end

  def up
    Role.reset_column_information
    Role.find_or_create_by!(name: 'wholesale')
  end

  def down
    # The role may predate this migration and carry user assignments; leave it.
  end
end
