require "test_helper"
require "shopify_extract/scope_verifier"

class ShopifyExtract::ScopeVerifierTest < ActiveSupport::TestCase
  test "passes when all required scopes present" do
    client = Minitest::Mock.new
    client.expect :query, {
      "data" => {
        "currentAppInstallation" => {
          "accessScopes" => ShopifyExtract::ScopeVerifier::REQUIRED.map { |h| { "handle" => h } }
        }
      }
    }, [String]

    assert_nothing_raised do
      ShopifyExtract::ScopeVerifier.new(client).call
    end
  end

  test "raises with missing scope list" do
    client = Minitest::Mock.new
    client.expect :query, {
      "data" => {
        "currentAppInstallation" => {
          "accessScopes" => [{ "handle" => "read_products" }]
        }
      }
    }, [String]

    err = assert_raises(ShopifyExtract::ScopeVerifier::MissingScopesError) do
      ShopifyExtract::ScopeVerifier.new(client).call
    end
    assert_includes err.message, "read_themes"
    assert_includes err.message, "read_translations"
  end

  test "REQUIRED scopes match spec" do
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_products"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_content"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_online_store_pages"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_themes"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_locales"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_translations"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_metaobjects"
    assert_includes ShopifyExtract::ScopeVerifier::REQUIRED, "read_files"
  end
end
