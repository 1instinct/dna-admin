require "test_helper"

class PharmacyOrderTest < ActiveSupport::TestCase
  test "valid pharmacy order" do
    order = build(:pharmacy_order)
    assert order.valid?
  end

  test "requires patient_mapping" do
    order = build(:pharmacy_order, patient_mapping: nil)
    assert_not order.valid?
  end

  test "requires honeybee_order_number" do
    order = build(:pharmacy_order, honeybee_order_number: nil)
    assert_not order.valid?
  end

  test "honeybee_order_number is unique" do
    create(:pharmacy_order, honeybee_order_number: "HB-001")
    duplicate = build(:pharmacy_order, honeybee_order_number: "HB-001")
    assert_not duplicate.valid?
  end
end
