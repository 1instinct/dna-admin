require "webmock/minitest"

module ShopifyFixtureHelper
  SHOPIFY_GRAPHQL_URL = "https://cntrlplus-md-integration-dev.myshopify.com/admin/api/2026-01/graphql.json".freeze
  SHOPIFY_REST_THEMES_URL = "https://cntrlplus-md-integration-dev.myshopify.com/admin/api/2026-01/themes.json".freeze

  def stub_shopify_graphql(query_match:, fixture:, status: 200)
    body = File.read(Rails.root.join("test/fixtures/shopify_api/#{fixture}"))
    stub_request(:post, SHOPIFY_GRAPHQL_URL)
      .with { |req| req.body.include?(query_match) }
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def setup_extract_env
    ENV["SHOPIFY_API_BASE"] = "https://cntrlplus-md-integration-dev.myshopify.com"
    ENV["SHOPIFY_ACCESS_TOKEN"] = "shpca_test"
    ENV["SHOPIFY_API_VERSION"] = "2026-01"
  end
end
