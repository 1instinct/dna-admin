require "shopify_extract/resource_extractor_base"
require "shopify_extract/mappers/menu_item_mapper"
require "shopify_extract/query_loader"

module ShopifyExtract
  module Resources
    class MenusExtractor < ResourceExtractorBase
      protected

      def resource_name
        "menus"
      end

      def fetch_page(cursor:)
        # Menus are not cursor-paginated in practice (small set). Single call.
        market = @topology[:locale_to_market][@locale]
        country = market["country_code"]
        language = @locale.upcase

        response = @client.query(
          QueryLoader.load("menus"),
          variables: { country: country, language: language }
        )

        menus = response.dig("data", "menus", "edges") || []
        {
          records: menus.map { |e| e["node"] },
          end_cursor: nil,
          has_next_page: false
        }
      end

      def map_record(shopify_menu)
        {
          _shopify: { gid: shopify_menu["id"], handle: shopify_menu["handle"] },
          code: shopify_menu["handle"],
          label: shopify_menu["title"],
          items: (shopify_menu["items"] || []).each_with_index.map do |item, i|
            Mappers::MenuItemMapper.call(item, position: i + 1)
          end
        }.deep_stringify_keys
      end
    end
  end
end
