require "test_helper"
require "shopify_extract/mappers/taxon_mapper"

class ShopifyExtract::Mappers::TaxonMapperTest < ActiveSupport::TestCase
  def minimal_collection
    {
      "id" => "gid://shopify/Collection/1",
      "handle" => "starter-kits",
      "title" => "Starter Kits",
      "descriptionHtml" => "<p>All starter kits</p>",
      "sortOrder" => "MANUAL",
      "seo" => { "title" => "Starter Kits SEO", "description" => "Kits seo desc" },
      "products" => { "edges" => [] }
    }
  end

  test "maps title to name" do
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal_collection)
    assert_equal "Starter Kits", result[:name]
  end

  test "maps handle to code" do
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal_collection)
    assert_equal "starter-kits", result[:code]
  end

  test "maps descriptionHtml to description" do
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal_collection)
    assert_equal "<p>All starter kits</p>", result[:description]
  end

  test "maps seo to meta fields" do
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal_collection)
    assert_equal "Starter Kits SEO", result[:meta_title]
    assert_equal "Kits seo desc", result[:meta_description]
  end

  test "preserves _shopify context with handle, rule_set, and sort_order" do
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal_collection)
    assert_equal "gid://shopify/Collection/1", result[:_shopify][:gid]
    assert_equal "starter-kits", result[:_shopify][:handle]
    assert_equal "MANUAL", result[:_shopify][:sort_order]
  end

  test "extracts product handles with positions" do
    collection = minimal_collection.merge(
      "products" => {
        "edges" => [
          { "node" => { "handle" => "kit-a" } },
          { "node" => { "handle" => "kit-b" } },
          { "node" => { "handle" => "kit-c" } }
        ]
      }
    )
    result = ShopifyExtract::Mappers::TaxonMapper.call(collection)
    assert_equal 3, result[:product_handles].length
    assert_equal "kit-a", result[:product_handles][0][:handle]
    assert_equal 1, result[:product_handles][0][:position]
    assert_equal "kit-c", result[:product_handles][2][:handle]
    assert_equal 3, result[:product_handles][2][:position]
  end

  test "preserves rule_set for smart collections" do
    collection = minimal_collection.merge(
      "ruleSet" => {
        "appliedDisjunctively" => true,
        "rules" => [
          { "column" => "TAG", "condition" => "starter-kit", "relation" => "EQUALS" }
        ]
      }
    )
    result = ShopifyExtract::Mappers::TaxonMapper.call(collection)
    assert_equal true, result[:_shopify][:rule_set]["appliedDisjunctively"]
    assert_equal 1, result[:_shopify][:rule_set]["rules"].length
  end

  test "handles missing optional fields gracefully" do
    minimal = {
      "id" => "gid://shopify/Collection/2",
      "handle" => "all",
      "title" => "All"
    }
    result = ShopifyExtract::Mappers::TaxonMapper.call(minimal)
    assert_equal "All", result[:name]
    assert_nil result[:description]
    assert_equal [], result[:product_handles]
  end
end
