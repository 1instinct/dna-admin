require "test_helper"
require "shopify_extract/finalizer"
require "shopify_extract/page_partial_writer"
require "tmpdir"

class ShopifyExtract::FinalizerTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    @writer.write_page(1, [{ "slug" => "a" }, { "slug" => "b" }])
    @writer.write_page(2, [{ "slug" => "c" }])
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "writes final file with _meta block" do
    finalizer = ShopifyExtract::Finalizer.new(
      dir: @tmp,
      resource: "products",
      locale: "en",
      store_code: "cntrl-en",
      country_code: "US",
      currency: "USD",
      schema_version: "1.0.0",
      api_version: "2026-01"
    )
    finalizer.call

    path = File.join(@tmp, "en", "products.json")
    assert File.exist?(path)

    data = JSON.parse(File.read(path))
    assert_equal "en", data["_meta"]["locale"]
    assert_equal 3, data["_meta"]["count"]
    assert_equal "USD", data["_meta"]["currency"]
    assert_equal ["a", "b", "c"], data["products"].map { |p| p["slug"] }
  end

  test "deletes page partials after finalization by default" do
    finalizer = ShopifyExtract::Finalizer.new(
      dir: @tmp, resource: "products", locale: "en",
      store_code: "cntrl-en", country_code: "US", currency: "USD",
      schema_version: "1.0.0", api_version: "2026-01"
    )
    finalizer.call

    assert_equal [], @writer.list_pages
  end

  test "preserves page partials when keep_partials is true" do
    finalizer = ShopifyExtract::Finalizer.new(
      dir: @tmp, resource: "products", locale: "en",
      store_code: "cntrl-en", country_code: "US", currency: "USD",
      schema_version: "1.0.0", api_version: "2026-01",
      keep_partials: true
    )
    finalizer.call

    assert_equal [1, 2], @writer.list_pages
  end

  test "supports custom output_key for taxonomies" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "taxonomies", locale: "en")
    writer.write_page(1, [{ "name" => "Kits" }])

    finalizer = ShopifyExtract::Finalizer.new(
      dir: @tmp, resource: "taxonomies", locale: "en",
      store_code: "cntrl-en", country_code: "US", currency: "USD",
      schema_version: "1.0.0", api_version: "2026-01",
      output_key: "taxonomies"
    )
    finalizer.call

    data = JSON.parse(File.read(File.join(@tmp, "en", "taxonomies.json")))
    assert_equal 1, data["taxonomies"].length
  end
end
