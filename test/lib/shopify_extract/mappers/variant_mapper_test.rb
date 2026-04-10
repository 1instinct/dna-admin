require "test_helper"
require "shopify_extract/mappers/variant_mapper"

class ShopifyExtract::Mappers::VariantMapperTest < ActiveSupport::TestCase
  def minimal_variant
    {
      "id" => "gid://shopify/ProductVariant/1",
      "sku" => "SKU-1",
      "price" => "49.99",
      "compareAtPrice" => nil,
      "inventoryQuantity" => 10,
      "weight" => 0.5,
      "weightUnit" => "KILOGRAMS",
      "selectedOptions" => []
    }
  end

  test "maps sku and price" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" })
    assert_equal "SKU-1", result[:sku]
    assert_equal "49.99", result[:price]
  end

  test "applies market currency" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "EUR" })
    assert_equal "EUR", result[:currency]
  end

  test "maps inventoryQuantity to stock_total_on_hand" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" })
    assert_equal 10, result[:stock_total_on_hand]
  end

  test "preserves _shopify gid" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" })
    assert_equal "gid://shopify/ProductVariant/1", result[:_shopify][:gid]
  end

  test "is_master defaults to false" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" })
    assert_equal false, result[:is_master]
  end

  test "is_master can be set to true" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" }, is_master: true)
    assert_equal true, result[:is_master]
  end

  test "normalizes weight unit to kg" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant, market: { "currency" => "USD" })
    assert_equal "kg", result[:weight_unit]
  end

  test "maps selectedOptions to option_values" do
    variant = minimal_variant.merge(
      "selectedOptions" => [{ "name" => "Size", "value" => "Small" }]
    )
    result = ShopifyExtract::Mappers::VariantMapper.call(variant, market: { "currency" => "USD" })
    assert_equal 1, result[:option_values].length
    assert_equal "size", result[:option_values][0][:option_type_name]
    assert_equal "small", result[:option_values][0][:name]
    assert_equal "Small", result[:option_values][0][:presentation]
  end

  test "handles nil inventoryQuantity" do
    result = ShopifyExtract::Mappers::VariantMapper.call(minimal_variant.merge("inventoryQuantity" => nil), market: { "currency" => "USD" })
    assert_equal 0, result[:stock_total_on_hand]
  end
end
