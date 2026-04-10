require "test_helper"
require "shopify_extract/url_normalizer"

class ShopifyExtract::UrlNormalizerTest < ActiveSupport::TestCase
  test "strips v query param" do
    url = "https://cdn.shopify.com/s/files/1/0001/products/kit.jpg?v=1234567890"
    assert_equal "https://cdn.shopify.com/s/files/1/0001/products/kit.jpg",
                 ShopifyExtract::UrlNormalizer.call(url)
  end

  test "strips width and height params" do
    url = "https://cdn.shopify.com/s/files/1/kit.jpg?width=500&height=500"
    assert_equal "https://cdn.shopify.com/s/files/1/kit.jpg",
                 ShopifyExtract::UrlNormalizer.call(url)
  end

  test "strips combined params" do
    url = "https://cdn.shopify.com/s/files/1/kit.jpg?v=123&width=500&crop=center"
    assert_equal "https://cdn.shopify.com/s/files/1/kit.jpg",
                 ShopifyExtract::UrlNormalizer.call(url)
  end

  test "preserves path and hostname" do
    url = "https://cdn.shopify.com/s/files/1/0001/0002/products/kit.jpg?v=1"
    result = ShopifyExtract::UrlNormalizer.call(url)
    assert_equal "/s/files/1/0001/0002/products/kit.jpg", URI.parse(result).path
    assert_equal "cdn.shopify.com", URI.parse(result).host
  end

  test "handles urls with no query params" do
    url = "https://cdn.shopify.com/s/files/1/kit.jpg"
    assert_equal url, ShopifyExtract::UrlNormalizer.call(url)
  end

  test "returns nil for nil input" do
    assert_nil ShopifyExtract::UrlNormalizer.call(nil)
  end

  test "raises on invalid URL" do
    assert_raises(URI::InvalidURIError) do
      ShopifyExtract::UrlNormalizer.call("not a url at all")
    end
  end
end
