require "test_helper"
require "shopify_extract/resources/menus_extractor"
require "shopify_extract/client/graphql_client"
require "shopify_extract/config"
require_relative "../../../helpers/shopify_fixture_helper"
require "tmpdir"

class ShopifyExtract::Resources::MenusExtractorTest < ActiveSupport::TestCase
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

  test "extracts header and footer menus" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/menus.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::MenusExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "menus.json")))
    assert_equal 2, output["menus"].length
    assert_equal "main-menu", output["menus"][0]["code"]
    assert_equal "footer", output["menus"][1]["code"]
  end

  test "preserves nested menu tree" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/menus.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    ShopifyExtract::Resources::MenusExtractor.new(
      config: @config, client: client, locale: "en", topology: @topology
    ).call

    output = JSON.parse(File.read(File.join(@tmp, "en", "menus.json")))
    main_menu = output["menus"][0]
    shop_item = main_menu["items"].find { |i| i["label"] == "Shop" }
    assert_equal 1, shop_item["children"].length
    assert_equal "Starter Kits", shop_item["children"][0]["label"]
  end
end
