require "shopify_extract/resource_extractor_base"
require "shopify_extract/mappers/product_mapper"
require "shopify_extract/query_loader"

module ShopifyExtract
  module Resources
    class ProductsExtractor < ResourceExtractorBase
      PAGE_SIZE = 50

      protected

      def resource_name
        "products"
      end

      def fetch_page(cursor:)
        market = @topology[:locale_to_market][@locale]
        country = market["country_code"]
        language = @locale.upcase

        response = @client.query(
          QueryLoader.load("products"),
          variables: { first: PAGE_SIZE, after: cursor, country: country, language: language }
        )

        products = response.dig("data", "products")
        {
          records: (products["edges"] || []).map { |e| e["node"] },
          end_cursor: products.dig("pageInfo", "endCursor"),
          has_next_page: products.dig("pageInfo", "hasNextPage") || false
        }
      end

      def map_record(shopify_product)
        market = @topology[:locale_to_market][@locale]
        Mappers::ProductMapper.call(shopify_product, market: market).deep_stringify_keys
      end
    end
  end
end
