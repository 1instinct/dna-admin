require "shopify_extract/mappers/variant_mapper"

module ShopifyExtract
  module Mappers
    module ProductMapper
      HEALTHCARE_LIFTED = %w[requires_consultation].freeze
      ACRONYMS = %w[NDC SKU URL HTML SEO FDA HSA HIPAA].freeze

      def self.call(shopify, market:)
        metafields = extract_metafields(shopify)

        {
          _shopify: {
            gid: shopify["id"],
            handle: shopify["handle"],
            original_title: shopify["title"],
            vendor: shopify["vendor"],
            product_type: shopify["productType"]
          },
          name: shopify["title"],
          slug: shopify["handle"],
          description: shopify["descriptionHtml"],
          meta_title: shopify.dig("seo", "title"),
          meta_description: shopify.dig("seo", "description"),
          meta_keywords: nil,
          available_on: shopify["publishedAt"],
          discontinue_on: nil,
          promotionable: true,
          tags: shopify["tags"] || [],
          requires_consultation: boolean_metafield(metafields, "custom", "requires_consultation"),
          tax_category_name: shopify["productType"].to_s.presence || "Default",
          shipping_category_name: "Default",
          taxon_memberships: [], # populated by collection extractor
          option_types: map_option_types(shopify["options"]),
          variants: map_variants(shopify, market),
          images: map_images(shopify),
          product_properties: build_product_properties(metafields)
        }
      end

      def self.extract_metafields(shopify)
        (shopify.dig("metafields", "edges") || []).map { |e| e["node"] }
      end

      def self.boolean_metafield(metafields, namespace, key)
        mf = metafields.find { |m| m["namespace"] == namespace && m["key"] == key }
        return false if mf.nil?
        mf["value"] == "true"
      end

      def self.build_product_properties(metafields)
        filtered = metafields.reject do |m|
          m["namespace"] == "custom" && HEALTHCARE_LIFTED.include?(m["key"])
        end

        filtered.each_with_index.map do |m, i|
          {
            property_name: m["key"],
            presentation: humanize_key(m["key"]),
            value: m["value"],
            position: i + 1
          }
        end
      end

      def self.humanize_key(key)
        key.to_s.tr("_", " ").split.map do |word|
          if ACRONYMS.include?(word.upcase)
            word.upcase
          else
            word.capitalize
          end
        end.join(" ")
      end

      def self.map_option_types(options)
        (options || []).each_with_index.map do |opt, i|
          {
            name: opt["name"]&.downcase,
            presentation: opt["name"],
            position: i + 1
          }
        end
      end

      def self.map_variants(shopify, market)
        (shopify.dig("variants", "edges") || []).each_with_index.map do |e, i|
          VariantMapper.call(e["node"], market: market, is_master: i == 0)
        end
      end

      def self.map_images(shopify)
        (shopify.dig("images", "edges") || []).each_with_index.map do |e, i|
          node = e["node"]
          {
            _shopify: { gid: node["id"] },
            local_path: nil, # populated by MediaExtractor after download
            original_url: node["url"],
            alt_text: node["altText"],
            width: node["width"],
            height: node["height"],
            position: i + 1
          }
        end
      end
    end
  end
end
