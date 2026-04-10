module ShopifyExtract
  module Mappers
    module MenuItemMapper
      def self.call(shopify_item, position:)
        resource_type, resource_handle = resolve_resource(shopify_item)

        {
          label: shopify_item["title"],
          url: shopify_item["url"],
          position: position,
          resource_type: resource_type,
          resource_handle: resource_handle,
          children: (shopify_item["items"] || []).each_with_index.map do |child, i|
            call(child, position: i + 1)
          end
        }
      end

      def self.resolve_resource(item)
        type = item["type"]
        resource = item["resource"]
        return ["http", nil] if resource.nil?

        handle = resource["handle"]
        case type
        when "COLLECTION" then ["collection", handle]
        when "PRODUCT" then ["product", handle]
        when "PAGE" then ["page", handle]
        when "ARTICLE" then ["article", handle]
        when "BLOG" then ["blog", handle]
        else ["http", nil]
        end
      end
    end
  end
end
