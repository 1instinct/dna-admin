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
      f.request :retry,
                max: 3,
                interval: 1,
                backoff_factor: 2,
                retry_statuses: [429, 500, 502, 503, 504]
      f.response :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end
end
