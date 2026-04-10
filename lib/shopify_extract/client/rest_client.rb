require "net/http"
require "json"
require "uri"

module ShopifyExtract
  module Client
    class RestClient
      class Error < StandardError; end
      class NotFoundError < Error; end

      def initialize(config)
        @config = config
      end

      def list_themes
        body = get_json("#{@config.rest_base_url}/themes.json")
        body["themes"]
      end

      def fetch_theme_asset(theme_id:, key:)
        url = "#{@config.rest_base_url}/themes/#{theme_id}/assets.json?asset[key]=#{URI.encode_www_form_component(key)}"
        body = get_json(url)
        body["asset"]
      end

      private

      def get_json(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        req = Net::HTTP::Get.new(uri.request_uri)
        req["X-Shopify-Access-Token"] = @config.access_token

        response = http.request(req)

        case response.code.to_i
        when 404
          raise NotFoundError, "Not found: #{url}"
        when 200..299
          JSON.parse(response.body)
        else
          raise Error, "Unexpected HTTP #{response.code}: #{response.body}"
        end
      end
    end
  end
end
