# Application Insights integration for Azure monitoring.
# Custom metrics: webhook_received, webhook_processed,
# consultation_completed, prescription_status_change.
#
# Full SDK (applicationinsights gem) can be added later.
# Azure Container Apps forwards stdout to Log Analytics, so structured
# logging is sufficient for now.

if ENV["APPLICATIONINSIGHTS_CONNECTION_STRING"].present?
  Rails.application.config.after_initialize do
    Rails.logger.info "[AppInsights] Connection string present — telemetry enabled"
  end
end

# Helper module for tracking custom metrics from anywhere in the app
module CntrlTelemetry
  module_function

  def track_webhook(source:, status:)
    Rails.logger.info("telemetry.webhook_processed source=#{source} status=#{status}")
  end

  def webhook_received(source:)
    Rails.logger.info("telemetry.webhook_received source=#{source}")
  end

  def webhook_processed(source:, status:)
    track_webhook(source: source, status: status)
  end

  def track_consultation(outcome:)
    Rails.logger.info("telemetry.consultation_completed outcome=#{outcome}")
  end

  def consultation_completed(outcome:)
    track_consultation(outcome: outcome)
  end

  def track_prescription_change(from:, to:)
    Rails.logger.info("telemetry.prescription_status_change from=#{from} to=#{to}")
  end

  def prescription_status_change(from:, to:)
    track_prescription_change(from: from, to: to)
  end
end
