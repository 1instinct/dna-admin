module ShopifyExtract
  module Mappers
    module VariantMapper
      WEIGHT_UNITS = {
        "KILOGRAMS" => "kg",
        "GRAMS" => "g",
        "POUNDS" => "lb",
        "OUNCES" => "oz"
      }.freeze

      def self.call(shopify, market:, is_master: false)
        {
          _shopify: {
            gid: shopify["id"],
            original_sku: shopify["sku"]
          },
          sku: shopify["sku"],
          is_master: is_master,
          price: shopify["price"],
          compare_at_price: shopify["compareAtPrice"],
          currency: market["currency"],
          weight: shopify["weight"],
          weight_unit: WEIGHT_UNITS[shopify["weightUnit"]] || "kg",
          track_inventory: true,
          stock_total_on_hand: shopify["inventoryQuantity"] || 0,
          option_values: map_option_values(shopify["selectedOptions"])
        }
      end

      def self.map_option_values(options)
        (options || []).map do |opt|
          {
            option_type_name: opt["name"].to_s.downcase,
            name: opt["value"].to_s.downcase.gsub(/\s+/, "_"),
            presentation: opt["value"]
          }
        end
      end
    end
  end
end
