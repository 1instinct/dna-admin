require "test_helper"
require "shopify_extract/mappers/product_mapper"

class ShopifyExtract::Mappers::ProductMapperTest < ActiveSupport::TestCase
  def minimal_shopify_product
    {
      "id" => "gid://shopify/Product/123",
      "handle" => "pessary-kit",
      "title" => "Pessary Starter Kit",
      "descriptionHtml" => "<p>Description</p>",
      "vendor" => "Cntrl+",
      "productType" => "Medical Device",
      "tags" => ["starter-kit"],
      "publishedAt" => "2026-01-15T00:00:00Z",
      "seo" => { "title" => "SEO Title", "description" => "SEO Desc" },
      "variants" => { "edges" => [] },
      "images" => { "edges" => [] },
      "metafields" => { "edges" => [] },
      "options" => []
    }
  end

  def market
    { "currency" => "USD" }
  end

  test "maps title to name" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "Pessary Starter Kit", result[:name]
  end

  test "maps handle to slug" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "pessary-kit", result[:slug]
  end

  test "maps descriptionHtml to description" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "<p>Description</p>", result[:description]
  end

  test "maps seo to meta fields" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "SEO Title", result[:meta_title]
    assert_equal "SEO Desc", result[:meta_description]
  end

  test "maps publishedAt to available_on" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "2026-01-15T00:00:00Z", result[:available_on]
  end

  test "preserves tags" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal ["starter-kit"], result[:tags]
  end

  test "preserves _shopify context block" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "gid://shopify/Product/123", result[:_shopify][:gid]
    assert_equal "pessary-kit", result[:_shopify][:handle]
    assert_equal "Cntrl+", result[:_shopify][:vendor]
    assert_equal "Medical Device", result[:_shopify][:product_type]
  end

  test "vendor is not a Spree column but preserved in _shopify" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    refute result.key?(:vendor_name)
    assert_equal "Cntrl+", result[:_shopify][:vendor]
  end

  test "lifts custom.requires_consultation metafield to top-level boolean" do
    shopify = minimal_shopify_product.merge(
      "metafields" => {
        "edges" => [
          { "node" => { "namespace" => "custom", "key" => "requires_consultation", "value" => "true", "type" => "boolean" } }
        ]
      }
    )
    result = ShopifyExtract::Mappers::ProductMapper.call(shopify, market: market)
    assert_equal true, result[:requires_consultation]
    assert_equal [], result[:product_properties]
  end

  test "requires_consultation defaults to false when absent" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal false, result[:requires_consultation]
  end

  test "flattens non-healthcare metafields to product_properties with acronym handling" do
    shopify = minimal_shopify_product.merge(
      "metafields" => {
        "edges" => [
          { "node" => { "namespace" => "custom", "key" => "ndc_code", "value" => "02400000713", "type" => "single_line_text_field" } },
          { "node" => { "namespace" => "custom", "key" => "clinical_trials", "value" => "Phase III", "type" => "single_line_text_field" } }
        ]
      }
    )
    result = ShopifyExtract::Mappers::ProductMapper.call(shopify, market: market)
    assert_equal 2, result[:product_properties].length

    ndc = result[:product_properties].find { |p| p[:property_name] == "ndc_code" }
    assert_equal "02400000713", ndc[:value]
    assert_equal "NDC Code", ndc[:presentation]
    assert_equal 1, ndc[:position]

    trials = result[:product_properties].find { |p| p[:property_name] == "clinical_trials" }
    assert_equal "Clinical Trials", trials[:presentation]
  end

  test "emits tax_category_name and shipping_category_name as hints" do
    result = ShopifyExtract::Mappers::ProductMapper.call(minimal_shopify_product, market: market)
    assert_equal "Medical Device", result[:tax_category_name]
    assert_equal "Default", result[:shipping_category_name]
  end

  test "maps images with position and original_url" do
    shopify = minimal_shopify_product.merge(
      "images" => {
        "edges" => [
          {
            "node" => {
              "id" => "gid://shopify/MediaImage/42",
              "url" => "https://cdn.shopify.com/kit.jpg?v=123",
              "altText" => "Starter kit",
              "width" => 2000,
              "height" => 2000
            }
          }
        ]
      }
    )
    result = ShopifyExtract::Mappers::ProductMapper.call(shopify, market: market)
    assert_equal 1, result[:images].length
    img = result[:images][0]
    assert_equal "https://cdn.shopify.com/kit.jpg?v=123", img[:original_url]
    assert_equal "Starter kit", img[:alt_text]
    assert_equal 2000, img[:width]
    assert_equal 1, img[:position]
    assert_nil img[:local_path]
  end

  test "maps variants" do
    shopify = minimal_shopify_product.merge(
      "variants" => {
        "edges" => [
          {
            "node" => {
              "id" => "gid://shopify/ProductVariant/1",
              "sku" => "CNTRL-KIT-S",
              "price" => "49.99",
              "compareAtPrice" => nil,
              "inventoryQuantity" => 120,
              "weight" => 0.5,
              "weightUnit" => "KILOGRAMS",
              "selectedOptions" => [{ "name" => "Size", "value" => "Small" }]
            }
          }
        ]
      }
    )

    result = ShopifyExtract::Mappers::ProductMapper.call(shopify, market: market)
    v = result[:variants][0]
    assert_equal "CNTRL-KIT-S", v[:sku]
    assert_equal "49.99", v[:price]
    assert_equal "USD", v[:currency]
    assert_equal 120, v[:stock_total_on_hand]
    assert_equal "gid://shopify/ProductVariant/1", v[:_shopify][:gid]
  end
end
