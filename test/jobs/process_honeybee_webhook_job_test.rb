require "test_helper"

class ProcessHoneybeeWebhookJobTest < ActiveSupport::TestCase
  setup do
    @user = create(:spree_user, email: "jane.doe@example.com")
    PendingCustomer.create!(
      email: "jane.doe@example.com",
      spree_user: @user,
      mdi_encounter_id: "enc_test_001"
    )
  end

  test "RX_RECEIVED: creates prescription and patient mapping" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_received.json"))
    )

    assert_difference ["Prescription.count", "PatientMapping.count"], 1 do
      ProcessHoneybeeWebhookJob.perform_now(payload)
    end

    prescription = Prescription.last
    assert_equal 10001, prescription.prescription_id
    assert_equal "Cntrl+ Pessary Starter Kit", prescription.drug_name
    assert_equal "02400000713", prescription.ndc
    assert_equal "pending", prescription.status

    mapping = PatientMapping.last
    assert_equal "hb_pat_001", mapping.honeybee_patient_id
    assert_equal @user, mapping.spree_user
  end

  test "RX_RECEIVED: links patient mapping to user via PendingCustomer" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_received.json"))
    )

    ProcessHoneybeeWebhookJob.perform_now(payload)

    mapping = PatientMapping.find_by(honeybee_patient_id: "hb_pat_001")
    assert_equal @user, mapping.spree_user
  end

  test "RX_RECEIVED: skips device-only NDCs via dedup service" do
    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_received.json"))
    )
    payload["medication_requests"][0]["ndc"] = "02400000714"

    assert_no_difference "Prescription.count" do
      ProcessHoneybeeWebhookJob.perform_now(payload)
    end
  end

  test "RX_UPDATED: updates prescription status" do
    mapping = create(:patient_mapping, honeybee_patient_id: "hb_pat_001")
    create(:prescription, patient_mapping: mapping, prescription_id: 10001, status: :pending)

    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_rx_updated.json"))
    )

    ProcessHoneybeeWebhookJob.perform_now(payload)

    prescription = Prescription.find_by(prescription_id: 10001)
    assert_equal "filling", prescription.status
  end

  test "SHIPMENT_UPDATED: updates pharmacy order with tracking" do
    mapping = create(:patient_mapping, honeybee_patient_id: "hb_pat_001")
    create(:pharmacy_order,
      patient_mapping: mapping,
      honeybee_order_number: "HB-100001"
    )

    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_shipment_updated.json"))
    )

    ProcessHoneybeeWebhookJob.perform_now(payload)

    order = PharmacyOrder.find_by(honeybee_order_number: "HB-100001")
    assert_equal "UPS", order.shipment_data["carrier"]
    assert_equal "1Z999AA10123456784", order.shipment_data["tracking_number"]
  end

  test "ORDER_EXCEPTION: stores exception data" do
    mapping = create(:patient_mapping, honeybee_patient_id: "hb_pat_001")
    create(:pharmacy_order,
      patient_mapping: mapping,
      honeybee_order_number: "HB-100001"
    )

    payload = JSON.parse(
      File.read(Rails.root.join("test/fixtures/webhooks/honeybee_order_exception.json"))
    )

    ProcessHoneybeeWebhookJob.perform_now(payload)

    order = PharmacyOrder.find_by(honeybee_order_number: "HB-100001")
    assert_equal "AddressValidationFailed", order.exception_data["name"]
  end
end
