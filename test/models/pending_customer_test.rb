require "test_helper"

class PendingCustomerTest < ActiveSupport::TestCase
  test "valid pending customer" do
    pending = build(:pending_customer)
    assert pending.valid?
  end

  test "requires email" do
    pending = build(:pending_customer, email: nil)
    assert_not pending.valid?
  end

  test "email is unique" do
    create(:pending_customer, email: "patient@example.com")
    duplicate = build(:pending_customer, email: "patient@example.com")
    assert_not duplicate.valid?
  end

  test "requires mdi_encounter_id" do
    pending = build(:pending_customer, mdi_encounter_id: nil)
    assert_not pending.valid?
  end
end
