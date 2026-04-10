module ShopifyExtract
  class ScopeVerifier
    class MissingScopesError < StandardError; end

    REQUIRED = %w[
      read_products
      read_content
      read_online_store_pages
      read_themes
      read_locales
      read_translations
      read_metaobjects
      read_files
    ].freeze

    QUERY = <<~GRAPHQL.freeze
      query VerifyScopes {
        currentAppInstallation {
          accessScopes { handle }
        }
      }
    GRAPHQL

    def initialize(client)
      @client = client
    end

    def call
      response = @client.query(QUERY)
      granted = response.dig("data", "currentAppInstallation", "accessScopes").to_a.map { |s| s["handle"] }
      missing = REQUIRED - granted

      if missing.any?
        raise MissingScopesError, "Shopify token is missing required scopes: #{missing.join(", ")}"
      end

      true
    end
  end
end
