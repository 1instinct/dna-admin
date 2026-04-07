class ProcessMdiWebhookJob < ApplicationJob
  queue_as :critical

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotUnique

  PASS_EVENTS = %w[case_approved case_completed PASS].freeze
  FAIL_EVENTS = %w[case_cancelled FAIL].freeze

  def perform(payload)
    event_type = payload["event_type"]
    encounter_id = payload["encounter_id"]
    metadata = payload["metadata"] || {}
    patient = metadata["patient"] || {}
    email = patient["email"]

    status = resolve_status(event_type)

    case status
    when :pass
      handle_pass(encounter_id, email, patient, metadata)
    when :fail
      handle_fail(encounter_id, email)
    when :pending
      handle_pending(encounter_id, email, payload)
    end
  end

  private

  def resolve_status(event_type)
    return :pass if PASS_EVENTS.include?(event_type)
    return :fail if FAIL_EVENTS.include?(event_type)
    :pending
  end

  def handle_pass(encounter_id, email, patient, metadata)
    user = find_user(email)
    if user
      user.update!(
        consultation_status: :pass,
        consultation_completed_at: Time.current,
        mdi_encounter_id: encounter_id
      )
    end

    PendingCustomer.find_or_create_by!(email: email) do |pc|
      pc.spree_user = user
      pc.mdi_encounter_id = encounter_id
      pc.patient_info = {
        first_name: patient["first_name"],
        last_name: patient["last_name"],
        phone: patient["phone"]
      }.compact
    end
  end

  def handle_fail(encounter_id, email)
    user = find_user(email)
    return unless user

    user.update!(
      consultation_status: :fail,
      mdi_encounter_id: encounter_id
    )
  end

  def handle_pending(encounter_id, email, payload)
    user = find_user(email)
    if user
      user.update!(
        consultation_status: :pending,
        mdi_encounter_id: encounter_id
      )
    end

    RetryPendingEncounterJob.perform_later(encounter_id, email)
  end

  def find_user(email)
    return nil if email.blank?
    Spree::User.find_by(email: email)
  end
end
