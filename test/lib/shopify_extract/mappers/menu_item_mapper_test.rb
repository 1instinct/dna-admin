require "test_helper"
require "shopify_extract/mappers/menu_item_mapper"

class ShopifyExtract::Mappers::MenuItemMapperTest < ActiveSupport::TestCase
  test "maps label and url" do
    item = {
      "title" => "Shop",
      "url" => "/collections/all",
      "type" => "COLLECTION",
      "resource" => { "handle" => "all" },
      "items" => []
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal "Shop", result[:label]
    assert_equal "/collections/all", result[:url]
    assert_equal 1, result[:position]
  end

  test "resolves COLLECTION resource type and handle" do
    item = {
      "title" => "Starter Kits",
      "url" => "/collections/starter-kits",
      "type" => "COLLECTION",
      "resource" => { "handle" => "starter-kits" },
      "items" => []
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal "collection", result[:resource_type]
    assert_equal "starter-kits", result[:resource_handle]
  end

  test "resolves PRODUCT resource type" do
    item = {
      "title" => "Pessary Kit",
      "url" => "/products/pessary-kit",
      "type" => "PRODUCT",
      "resource" => { "handle" => "pessary-kit" },
      "items" => []
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal "product", result[:resource_type]
    assert_equal "pessary-kit", result[:resource_handle]
  end

  test "handles dangling resource reference (orphan) as http type" do
    item = {
      "title" => "Deleted Page",
      "url" => "/pages/deleted",
      "type" => "PAGE",
      "resource" => nil,
      "items" => []
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal "http", result[:resource_type]
    assert_nil result[:resource_handle]
    assert_equal "/pages/deleted", result[:url]
  end

  test "handles external http link type" do
    item = {
      "title" => "External",
      "url" => "https://example.com",
      "type" => "HTTP",
      "resource" => nil,
      "items" => []
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal "http", result[:resource_type]
    assert_nil result[:resource_handle]
  end

  test "recurses into nested children with correct positions" do
    item = {
      "title" => "Shop",
      "url" => "/collections/all",
      "type" => "COLLECTION",
      "resource" => { "handle" => "all" },
      "items" => [
        {
          "title" => "Kits",
          "url" => "/collections/kits",
          "type" => "COLLECTION",
          "resource" => { "handle" => "kits" },
          "items" => []
        },
        {
          "title" => "Refills",
          "url" => "/collections/refills",
          "type" => "COLLECTION",
          "resource" => { "handle" => "refills" },
          "items" => []
        }
      ]
    }
    result = ShopifyExtract::Mappers::MenuItemMapper.call(item, position: 1)
    assert_equal 2, result[:children].length
    assert_equal "Kits", result[:children][0][:label]
    assert_equal 1, result[:children][0][:position]
    assert_equal "Refills", result[:children][1][:label]
    assert_equal 2, result[:children][1][:position]
  end
end
