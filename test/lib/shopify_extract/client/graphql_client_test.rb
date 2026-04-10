require "test_helper"
require "shopify_extract/client/graphql_client"
require "shopify_extract/config"
require_relative "../../../helpers/shopify_fixture_helper"

class ShopifyExtract::Client::GraphqlClientTest < ActiveSupport::TestCase
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

  test "query executes against Shopify and returns parsed response" do
    stub_shopify_graphql(query_match: "Topology", fixture: "topology.json")
    client = ShopifyExtract::Client::GraphqlClient.new(@config)

    result = client.query("query Topology { shop { name } }")

    assert_equal "Cntrl+ Dev", result.dig("data", "shop", "name")
  end

  test "query passes variables" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .with { |req| body = JSON.parse(req.body); body["variables"] == { "first" => 10 } }
      .to_return(status: 200, body: '{"data":{}}', headers: { "Content-Type" => "application/json" })

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    client.query("query Q($first: Int!) { foo }", variables: { first: 10 })

    assert_requested :post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL
  end

  test "raises on HTTP 429" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(status: 429, body: "", headers: {})

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    assert_raises(ShopifyExtract::Client::GraphqlClient::ThrottleError) do
      client.query("query Q { foo }")
    end
  end

  test "raises on GraphQL errors in response" do
    stub_request(:post, ShopifyFixtureHelper::SHOPIFY_GRAPHQL_URL)
      .to_return(
        status: 200,
        body: '{"errors":[{"message":"Access denied"}]}',
        headers: { "Content-Type" => "application/json" }
      )

    client = ShopifyExtract::Client::GraphqlClient.new(@config)
    assert_raises(ShopifyExtract::Client::GraphqlClient::QueryError) do
      client.query("query Q { foo }")
    end
  end
end
