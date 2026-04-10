require "test_helper"
require "shopify_extract/topology_resolver"
require_relative "../../helpers/shopify_fixture_helper"

class ShopifyExtract::TopologyResolverTest < ActiveSupport::TestCase
  include ShopifyFixtureHelper

  def topology_response
    JSON.parse(File.read(Rails.root.join("test/fixtures/shopify_api/topology.json")))
  end

  test "resolves locale_to_market from API response" do
    client = Minitest::Mock.new
    client.expect :query, topology_response, [String]

    resolver = ShopifyExtract::TopologyResolver.new(client)
    topology = resolver.call

    assert_equal "US", topology[:locale_to_market]["en"]["country_code"]
    assert_equal "USD", topology[:locale_to_market]["en"]["currency"]
    assert_equal "DE", topology[:locale_to_market]["de"]["country_code"]
    assert_equal "EUR", topology[:locale_to_market]["de"]["currency"]
  end

  test "includes shop_locales list" do
    client = Minitest::Mock.new
    client.expect :query, topology_response, [String]

    resolver = ShopifyExtract::TopologyResolver.new(client)
    topology = resolver.call

    assert_equal ["en", "de", "fr", "it", "es"], topology[:shop_locales].map { |l| l["locale"] }
    assert_equal true, topology[:shop_locales].find { |l| l["locale"] == "en" }["primary"]
  end

  test "persists topology to _meta/topology.json" do
    tmp = Dir.mktmpdir
    client = Minitest::Mock.new
    client.expect :query, topology_response, [String]

    resolver = ShopifyExtract::TopologyResolver.new(client, output_dir: tmp)
    resolver.call

    path = File.join(tmp, "_meta", "topology.json")
    assert File.exist?(path)
    data = JSON.parse(File.read(path))
    assert_equal "US", data["locale_to_market"]["en"]["country_code"]
  ensure
    FileUtils.rm_rf(tmp)
  end
end
