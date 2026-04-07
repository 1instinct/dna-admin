require "test_helper"

class StarterKitDeduplicationServiceTest < ActiveSupport::TestCase
  setup do
    @patient_mapping = create(:patient_mapping, honeybee_patient_id: "hb_pat_dedup")
    @config = Rails.application.config.cntrl
    @bundle_ndc = @config.starter_kit["bundle_ndc"]
    @device_ndcs = @config.starter_kit["device_ndcs"]
  end

  test "allows kit bundle NDC with no recent orders" do
    assert StarterKitDeduplicationService.should_process?(
      "hb_pat_dedup", [@bundle_ndc]
    )
  end

  test "rejects device-only NDCs (waiting for bundle)" do
    @device_ndcs.each do |ndc|
      assert_not StarterKitDeduplicationService.should_process?(
        "hb_pat_dedup", [ndc]
      ), "Expected device NDC #{ndc} to be rejected"
    end
  end

  test "rejects kit bundle if recent order exists within dedup window" do
    create(:pharmacy_order,
      patient_mapping: @patient_mapping,
      created_at: 5.minutes.ago
    )
    assert_not StarterKitDeduplicationService.should_process?(
      "hb_pat_dedup", [@bundle_ndc]
    )
  end

  test "allows kit bundle if previous order is outside dedup window" do
    create(:pharmacy_order,
      patient_mapping: @patient_mapping,
      created_at: 15.minutes.ago
    )
    assert StarterKitDeduplicationService.should_process?(
      "hb_pat_dedup", [@bundle_ndc]
    )
  end

  test "allows non-kit products regardless of recent orders" do
    create(:pharmacy_order,
      patient_mapping: @patient_mapping,
      created_at: 1.minute.ago
    )
    assert StarterKitDeduplicationService.should_process?(
      "hb_pat_dedup", ["99999999999"]
    )
  end

  test "allows kit bundle + device NDCs together" do
    assert StarterKitDeduplicationService.should_process?(
      "hb_pat_dedup", [@bundle_ndc, @device_ndcs.first]
    )
  end

  test "returns true for unknown patient" do
    assert StarterKitDeduplicationService.should_process?(
      "unknown_patient_id", [@bundle_ndc]
    )
  end
end
