# Partial refunds and why an earning went void.
#   refunded_gross: the part of gross refunded so far (amount is recomputed on gross - refunded_gross)
#   void_reason:    refund | cancel | admin; a resume only brings back earnings voided by a cancel
class AddRefundsToCreatorEarnings < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_creator_earnings, :refunded_gross, :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :spree_creator_earnings, :void_reason, :string
  end
end
