require "test_helper"

class PatientMappingTest < ActiveSupport::TestCase
  test "valid patient mapping" do
    mapping = build(:patient_mapping)
    assert mapping.valid?
  end

  test "requires honeybee_patient_id" do
    mapping = build(:patient_mapping, honeybee_patient_id: nil)
    assert_not mapping.valid?
  end

  test "honeybee_patient_id is unique" do
    create(:patient_mapping, honeybee_patient_id: "HB-PAT-001")
    duplicate = build(:patient_mapping, honeybee_patient_id: "HB-PAT-001")
    assert_not duplicate.valid?
  end

  test "requires source" do
    mapping = build(:patient_mapping, source: nil)
    assert_not mapping.valid?
  end

  test "valid source values" do
    %w[rx_received mdi_webhook manual].each do |source|
      mapping = build(:patient_mapping, source: source)
      assert mapping.valid?, "Expected #{source} to be valid"
    end
  end

  test "history defaults to empty array" do
    mapping = PatientMapping.new
    assert_equal [], mapping.history
  end
end
