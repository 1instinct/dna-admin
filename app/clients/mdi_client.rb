class MdiClient
  class PendingError < StandardError; end

  def initialize
    @base_url = ENV.fetch("MDI_API_BASE", "https://api.mdintegrations.com/v1")
    @client_id = ENV.fetch("MDI_CLIENT_ID")
    @client_secret = ENV.fetch("MDI_CLIENT_SECRET")
  end

  def fetch_encounter(encounter_id)
    response = connection.get("encounters/#{encounter_id}")
    response.body
  end

  private

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.request :json
      f.request :authorization, :basic, @client_id, @client_secret
      f.response :json
      f.response :raise_error
      f.request :retry,
                max: 3,
                interval: 0.1,
                backoff_factor: 2,
                exceptions: [Faraday::ServerError, Faraday::TimeoutError, Faraday::ConnectionFailed]
      f.adapter Faraday.default_adapter
    end
  end
end
