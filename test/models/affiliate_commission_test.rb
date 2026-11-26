require 'test_helper'

class AffiliateCommissionTest < ActiveSupport::TestCase
  test 'sweep! approves only pending commissions past approvable_at' do
    due = create(:affiliate_commission, state: 'pending', approvable_at: 1.minute.ago)
    later = create(:affiliate_commission, state: 'pending', approvable_at: 1.day.from_now)
    void = create(:affiliate_commission, state: 'void', approvable_at: 1.day.ago)
    paid = create(:affiliate_commission, state: 'paid', approvable_at: 1.day.ago)

    AffiliateCommission.sweep!

    assert_equal 'approved', due.reload.state
    assert_equal 'pending', later.reload.state
    assert_equal 'void', void.reload.state
    assert_equal 'paid', paid.reload.state
  end

  test 'one commission per order' do
    first = create(:affiliate_commission)
    dup = build(:affiliate_commission, order: first.order)
    refute dup.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test 'state must be pending, approved, paid or void' do
    refute build(:affiliate_commission, state: 'payable').valid?
  end

  test 'order_masked shows only the last four characters' do
    commission = create(:affiliate_commission)
    commission.order.update_column(:number, 'R123456789')
    assert_equal '****6789', commission.order_masked
  end
end
