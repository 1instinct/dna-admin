class HealthController < ActionController::API
  # GET /health
  # Used by Azure Container Apps health probes and monitoring.
  # Checks database and Redis connectivity.
  def show
    checks = {
      status: "ok",
      version: ENV.fetch("VERSION", "dev"),
      git_sha: ENV.fetch("GIT_SHA", "unknown"),
      timestamp: Time.current.iso8601,
      checks: {}
    }

    # Database check
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      checks[:checks][:database] = "ok"
    rescue StandardError => e
      checks[:checks][:database] = "error"
      checks[:status] = "degraded"
    end

    # Redis check
    begin
      Sidekiq.redis { |conn| conn.ping }
      checks[:checks][:redis] = "ok"
    rescue StandardError => e
      checks[:checks][:redis] = "error"
      checks[:status] = "degraded"
    end

    status_code = checks[:status] == "ok" ? :ok : :service_unavailable
    render json: checks, status: status_code
  end
end
