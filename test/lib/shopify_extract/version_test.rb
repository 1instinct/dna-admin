require "test_helper"
require "shopify_extract/version"

class ShopifyExtract::VersionTest < ActiveSupport::TestCase
  test "SCHEMA_VERSION is a semver string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, ShopifyExtract::SCHEMA_VERSION)
  end

  test "SCHEMA_VERSION is 1.0.0 at initial release" do
    assert_equal "1.0.0", ShopifyExtract::SCHEMA_VERSION
  end
end
