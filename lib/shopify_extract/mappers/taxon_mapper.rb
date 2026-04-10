module ShopifyExtract
  module Mappers
    module TaxonMapper
      def self.call(shopify)
        {
          _shopify: {
            gid: shopify["id"],
            handle: shopify["handle"],
            rule_set: shopify["ruleSet"],
            sort_order: shopify["sortOrder"]
          },
          name: shopify["title"],
          code: shopify["handle"],
          description: shopify["descriptionHtml"],
          meta_title: shopify.dig("seo", "title"),
          meta_description: shopify.dig("seo", "description"),
          product_handles: extract_product_handles(shopify)
        }
      end

      def self.extract_product_handles(shopify)
        (shopify.dig("products", "edges") || []).each_with_index.map do |e, i|
          { handle: e.dig("node", "handle"), position: i + 1 }
        end
      end
    end
  end
end
