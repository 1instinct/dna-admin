class HoneybeeClient
  TOKEN_BUFFER_SECONDS = 60

  def initialize
    @api_base = ENV.fetch("HONEYBEE_API_BASE", "https://partners.honeybeehealth.com")
    @auth_base = ENV.fetch("HONEYBEE_AUTH_BASE", "https://auth.honeybeehealth.com")
    @client_id = ENV.fetch("HONEYBEE_CLIENT_ID")
    @client_secret = ENV.fetch("HONEYBEE_SECRET_KEY")
  end

  def fetch_order(order_id)
    response = api_connection.get("v1/orders/#{order_id}")
    response.body
  end

  private

  def api_connection
    @api_connection ||= Faraday.new(url: @api_base) do |f|
      f.request :json
      f.request :authorization, :bearer, -> { access_token }
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

  def access_token
    cached = REDIS.get("honeybee:oauth_token")
    return cached if cached.present?

    token_data = fetch_token
    ttl = [token_data["expires_in"].to_i - TOKEN_BUFFER_SECONDS, 60].max

    REDIS.set("honeybee:oauth_token", token_data["access_token"], ex: ttl)
    token_data["access_token"]
  end

  def fetch_token
    response = auth_connection.post("oauth/token") do |req|
      req.body = {
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret
      }
    end
    response.body
  end

  def auth_connection
    Faraday.new(url: @auth_base) do |f|
      f.request :url_encoded
      f.response :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end
end
