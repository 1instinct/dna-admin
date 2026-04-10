require "shopify_extract/resource_extractor_base"
require "shopify_extract/mappers/taxon_mapper"
require "shopify_extract/query_loader"

module ShopifyExtract
  module Resources
    class CollectionsExtractor < ResourceExtractorBase
      PAGE_SIZE = 50

      protected

      def resource_name
        "collections"
      end

      # Override output_key so the final file has "taxonomies" key, not "collections"
      def output_key
        "taxonomies"
      end

      def fetch_page(cursor:)
        market = @topology[:locale_to_market][@locale]
        country = market["country_code"]
        language = @locale.upcase

        response = @client.query(
          QueryLoader.load("collections"),
          variables: { first: PAGE_SIZE, after: cursor, country: country, language: language }
        )

        collections = response.dig("data", "collections")
        {
          records: (collections["edges"] || []).map { |e| e["node"] },
          end_cursor: collections.dig("pageInfo", "endCursor"),
          has_next_page: collections.dig("pageInfo", "hasNextPage") || false
        }
      end

      def map_record(shopify_collection)
        Mappers::TaxonMapper.call(shopify_collection).deep_stringify_keys
      end
    end
  end
end
