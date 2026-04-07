class ProcessHoneybeeWebhookJob < ApplicationJob
  queue_as :critical

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotUnique

  def perform(payload)
    event_type = payload["event_type"]
    patient_id = payload["patient_id"]

    case event_type
    when "RX_RECEIVED"
      handle_rx_received(payload, patient_id)
    when "RX_UPDATED"
      handle_rx_updated(payload)
    when "SHIPMENT_UPDATED"
      handle_shipment_updated(payload)
    when "ORDER_EXCEPTION"
      handle_order_exception(payload)
    else
      Rails.logger.warn("Unknown Honeybee event type: #{event_type}")
    end
  end

  private

  def handle_rx_received(payload, patient_id)
    medication_requests = payload["medication_requests"] || []
    ndcs = medication_requests.map { |mr| mr["ndc"] }.compact

    return unless StarterKitDeduplicationService.should_process?(patient_id, ndcs)

    mapping = PatientMapping.find_or_initialize_by(honeybee_patient_id: patient_id)
    mapping.source = :rx_received unless mapping.persisted?

    unless mapping.spree_user
      pending = find_pending_customer(payload)
      mapping.spree_user = pending&.spree_user
      mapping.email = pending&.email
    end

    mapping.save!

    medication_requests.each do |med|
      Prescription.find_or_create_by!(prescription_id: med["prescription_id"]) do |rx|
        rx.patient_mapping = mapping
        rx.drug_name = med["drug_name"]
        rx.ndc = med["ndc"]
        rx.written_qty = med["written_qty"]
        rx.refills_left = med["refills_left"]
        rx.expire_date = med["expire_date"]
        rx.prescriber_name = med["prescriber_name"]
        rx.status = :pending
        rx.received_at = Time.current
      end
    end

    PharmacyOrder.find_or_create_by!(
      honeybee_order_number: "#{patient_id}-#{Time.current.to_i}"
    ) do |order|
      order.patient_mapping = mapping
      order.spree_user = mapping.spree_user
      order.prescription_ids = medication_requests.map { |mr| mr["prescription_id"] }
      order.status = "rx_received"
    end
  end

  def handle_rx_updated(payload)
    medication_requests = payload["medication_requests"] || []

    medication_requests.each do |med|
      prescription = Prescription.find_by(prescription_id: med["prescription_id"])
      next unless prescription

      new_status = map_rx_status(med["order_status"])
      prescription.update!(status: new_status) if new_status
    end
  end

  def handle_shipment_updated(payload)
    order_number = payload["order_number"]
    order = PharmacyOrder.find_by(honeybee_order_number: order_number)
    return unless order

    medication_requests = payload["medication_requests"] || []
    shipment = medication_requests.dig(0, "shipment") || {}

    order.update!(
      status: "shipped",
      shipment_data: {
        tracking_number: shipment["tracking_no"],
        carrier: shipment["carrier"],
        method: shipment["method"],
        shipped_at: shipment["shipped_at"]
      }
    )

    order.prescription_ids.each do |rx_id|
      Prescription.where(prescription_id: rx_id).update_all(status: Prescription.statuses[:shipped])
    end
  end

  def handle_order_exception(payload)
    order_number = payload["order_number"]
    order = PharmacyOrder.find_by(honeybee_order_number: order_number)
    return unless order

    exception = payload["exception"] || {}
    order.update!(
      status: "exception",
      exception_data: {
        name: exception["name"],
        message: exception["message"],
        order_actions: exception["order_actions"]
      }
    )
  end

  def find_pending_customer(payload)
    patient_id = payload["patient_id"]
    existing = PatientMapping.find_by(honeybee_patient_id: patient_id)
    if existing&.email
      return PendingCustomer.find_by(email: existing.email)
    end
    nil
  end

  def map_rx_status(honeybee_status)
    case honeybee_status&.downcase
    when "filling" then :filling
    when "ready" then :ready
    when "shipped" then :shipped
    when "delivered" then :delivered
    when "cancelled" then :cancelled
    end
  end
end
