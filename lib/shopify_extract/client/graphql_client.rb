require "net/http"
require "json"
require "uri"

module ShopifyExtract
  module Client
    class GraphqlClient
      class Error < StandardError; end
      class ThrottleError < Error; end
      class QueryError < Error; end

      def initialize(config)
        @config = config
      end

      def query(query_string, variables: {})
        uri = URI(@config.graphql_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        req = Net::HTTP::Post.new(uri.path)
        req["X-Shopify-Access-Token"] = @config.access_token
        req["Content-Type"] = "application/json"
        req.body = { query: query_string, variables: variables }.to_json

        response = http.request(req)

        case response.code.to_i
        when 429
          raise ThrottleError, "Shopify rate limit exceeded"
        when 200
          body = JSON.parse(response.body)
          if body["errors"]
            raise QueryError, "GraphQL errors: #{body["errors"].map { |e| e["message"] }.join(", ")}"
          end
          body
        else
          raise Error, "Unexpected HTTP #{response.code}: #{response.body}"
        end
      end
    end
  end
end
