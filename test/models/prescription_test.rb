require "test_helper"

class PrescriptionTest < ActiveSupport::TestCase
  test "valid prescription" do
    prescription = build(:prescription)
    assert prescription.valid?
  end

  test "requires patient_mapping" do
    prescription = build(:prescription, patient_mapping: nil)
    assert_not prescription.valid?
    assert_includes prescription.errors[:patient_mapping], "must exist"
  end

  test "requires prescription_id" do
    prescription = build(:prescription, prescription_id: nil)
    assert_not prescription.valid?
  end

  test "prescription_id is unique" do
    create(:prescription, prescription_id: 12345)
    duplicate = build(:prescription, prescription_id: 12345)
    assert_not duplicate.valid?
  end

  test "requires drug_name" do
    prescription = build(:prescription, drug_name: nil)
    assert_not prescription.valid?
  end

  test "requires ndc" do
    prescription = build(:prescription, ndc: nil)
    assert_not prescription.valid?
  end

  test "status defaults to pending" do
    prescription = Prescription.new
    assert_equal "pending", prescription.status
  end

  test "valid status transitions" do
    %w[pending ordered filling ready shipped delivered cancelled].each do |status|
      prescription = build(:prescription)
      prescription.status = status
      assert prescription.valid?, "Expected #{status} to be valid"
    end
  end
end
