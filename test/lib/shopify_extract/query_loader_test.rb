require "test_helper"
require "shopify_extract/query_loader"

class ShopifyExtract::QueryLoaderTest < ActiveSupport::TestCase
  test "loads topology query from file" do
    query = ShopifyExtract::QueryLoader.load("topology")
    assert_includes query, "query Topology"
    assert_includes query, "shopLocales"
    assert_includes query, "markets"
  end

  test "caches loaded queries" do
    ShopifyExtract::QueryLoader.clear_cache!
    q1 = ShopifyExtract::QueryLoader.load("topology")
    q2 = ShopifyExtract::QueryLoader.load("topology")
    assert_same q1, q2
  end

  test "raises for unknown query" do
    assert_raises(Errno::ENOENT) do
      ShopifyExtract::QueryLoader.load("nonexistent_query")
    end
  end
end
