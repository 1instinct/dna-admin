require "test_helper"
require "shopify_extract/resources/collections_extractor"
require "shopify_extract/client/graphql_client"
require "shopify_extract/config"
require_relative "../../../helpers/shopify_fixture_helper"
require "tmpdir"

class ShopifyExtract::Resources::CollectionsExtractorTest < ActiveSupport::TestCase
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
      locale_to_market: { "en" => { "country_code" => "US", "currency" => "USD" } }
    }
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "extracts collections and writes taxonomies.json" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/collections.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::CollectionsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "collections.json")))
    assert_equal 2, output["taxonomies"].length
    assert_equal "starter-kits", output["taxonomies"][0]["code"]
  end

  test "preserves product handles with positions for manual collections" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/collections.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::CollectionsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "collections.json")))
    starter_kits = output["taxonomies"].find { |t| t["code"] == "starter-kits" }
    assert_equal 2, starter_kits["product_handles"].length
    assert_equal "pessary-starter-kit", starter_kits["product_handles"][0]["handle"]
    assert_equal 1, starter_kits["product_handles"][0]["position"]
  end

  test "preserves rule_set for smart collections" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/collections.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::CollectionsExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "collections.json")))
    all = output["taxonomies"].find { |t| t["code"] == "all-products" }
    assert_not_nil all["_shopify"]["rule_set"]
    assert_equal true, all["_shopify"]["rule_set"]["appliedDisjunctively"]
  end
end
