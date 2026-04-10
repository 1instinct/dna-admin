require "test_helper"
require "shopify_extract/client/rest_client"
require "shopify_extract/config"
require_relative "../../../helpers/shopify_fixture_helper"

class ShopifyExtract::Client::RestClientTest < ActiveSupport::TestCase
  include ShopifyFixtureHelper

  setup do
    setup_extract_env
    @config = ShopifyExtract::Config.new(
      api_base: ENV.fetch("SHOPIFY_API_BASE"),
      access_token: ENV.fetch("SHOPIFY_ACCESS_TOKEN"),
      api_version: "2026-01",
      locales: ["en"],
      output_dir: Dir.mktmpdir,
      max_image_mb: 500,
      parallelism: 5
    )
  end

  test "list_themes returns parsed themes array" do
    stub_request(:get, ShopifyFixtureHelper::SHOPIFY_REST_THEMES_URL)
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/theme_main.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::RestClient.new(@config)
    themes = client.list_themes

    assert_equal 1, themes.length
    assert_equal "main", themes[0]["role"]
    assert_equal 136207515807, themes[0]["id"]
  end

  test "fetch_theme_asset returns asset content" do
    stub_request(:get, %r{/themes/123/assets\.json})
      .to_return(
        status: 200,
        body: File.read(Rails.root.join("test/fixtures/shopify_api/theme_settings_data.json")),
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::RestClient.new(@config)
    asset = client.fetch_theme_asset(theme_id: 123, key: "config/settings_data.json")

    assert_equal "config/settings_data.json", asset["key"]
    assert_includes asset["value"], "colors_accent_1"
  end

  test "raises on 404 for missing asset" do
    stub_request(:get, %r{/themes/123/assets\.json})
      .to_return(status: 404, body: '{"errors":"Not Found"}', headers: {})

    client = ShopifyExtract::Client::RestClient.new(@config)
    assert_raises(ShopifyExtract::Client::RestClient::NotFoundError) do
      client.fetch_theme_asset(theme_id: 123, key: "missing.json")
    end
  end
end
