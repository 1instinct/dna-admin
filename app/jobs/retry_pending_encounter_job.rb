class RetryPendingEncounterJob < ApplicationJob
  queue_as :default

  retry_on MdiClient::PendingError,
           wait: ->(executions) { [30, 60, 120][executions - 1] || 120 },
           attempts: 4

  discard_on(MdiClient::PendingError) do |job, error|
    encounter_id, email = job.arguments
    Rails.logger.warn(
      "Encounter #{encounter_id} still pending after max retries (email: #{email})"
    )
    LogWebhookEventJob.perform_later(
      event_type: "pending_timeout",
      source: "internal",
      payload: { encounter_id: encounter_id, email: email },
      error: "Max retries exceeded"
    )
  end

  def perform(encounter_id, email)
    client = MdiClient.new
    result = client.fetch_encounter(encounter_id)
    status = result["status"]&.upcase

    case status
    when "PASS"
      user = Spree::User.find_by(email: email)
      user&.update!(
        consultation_status: :pass,
        consultation_completed_at: Time.current,
        mdi_encounter_id: encounter_id
      )
    when "FAIL"
      user = Spree::User.find_by(email: email)
      user&.update!(
        consultation_status: :fail,
        mdi_encounter_id: encounter_id
      )
    else
      raise MdiClient::PendingError, "Encounter #{encounter_id} still pending (status: #{status})"
    end
  end
end
