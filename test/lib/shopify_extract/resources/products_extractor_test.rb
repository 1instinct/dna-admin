require "test_helper"
require "shopify_extract/resources/products_extractor"
require "shopify_extract/client/graphql_client"
require "shopify_extract/config"
require_relative "../../../helpers/shopify_fixture_helper"
require "tmpdir"

class ShopifyExtract::Resources::ProductsExtractorTest < ActiveSupport::TestCase
  include ShopifyFixtureHelper

  setup do
    @tmp = Dir.mktmpdir
    setup_extract_env
    @config = ShopifyExtract::Config.new(
      api_base: ENV.fetch("SHOPIFY_API_BASE"),
      access_token: ENV.fetch("SHOPIFY_ACCESS_TOKEN"),
      api_version: "2026-01",
      locales: ["en"],
      output_dir: @tmp,
      max_image_mb: 500,
      parallelism: 5
    )
    @topology = {
      locale_to_market: {
        "en" => { "country_code" => "US", "currency" => "USD" }
      }
    }
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "extracts all products across two pages" do
    page_1_body = File.read(Rails.root.join("test/fixtures/shopify_api/products_page_1.json"))
    page_2_body = File.read(Rails.root.join("test/fixtures/shopify_api/products_page_2.json"))

    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        { status: 200, body: page_1_body, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: page_2_body, headers: { "Content-Type" => "application/json" } }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    extractor = ShopifyExtract::Resources::ProductsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    )
    extractor.call

    output = JSON.parse(File.read(File.join(@tmp, "en", "products.json")))
    assert_equal 2, output["products"].length
    assert_equal ["pessary-starter-kit", "refill-kit"], output["products"].map { |p| p["slug"] }
  end

  test "maps product with healthcare lifting" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/products_page_1.json")).sub('"hasNextPage": true', '"hasNextPage": false'),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::ProductsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "products.json")))
    kit = output["products"][0]
    assert_equal true, kit["requires_consultation"]
    assert_equal 1, kit["product_properties"].length
    assert_equal "ndc_code", kit["product_properties"][0]["property_name"]
  end

  test "writes finalized file with _meta block" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/products_page_1.json")).sub('"hasNextPage": true', '"hasNextPage": false'),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::ProductsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "products.json")))
    assert_equal "en", output["_meta"]["locale"]
    assert_equal "USD", output["_meta"]["currency"]
    assert_equal 1, output["_meta"]["count"]
  end
end
