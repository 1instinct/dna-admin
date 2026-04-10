require "test_helper"
require "webmock/minitest"
require "shopify_extract/image_downloader"
require "shopify_extract/url_normalizer"
require "digest"
require "tmpdir"

class ShopifyExtract::ImageDownloaderTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
    @downloader = ShopifyExtract::ImageDownloader.new(base_dir: @tmp, locale: "en")
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "downloads image to content-addressable path" do
    stub_request(:get, "https://cdn.shopify.com/s/files/1/kit.jpg")
      .to_return(
        status: 200,
        body: "fake-image-bytes",
        headers: { "Content-Type" => "image/jpeg", "Content-Length" => "16" }
      )

    entry = @downloader.download("https://cdn.shopify.com/s/files/1/kit.jpg?v=123")

    expected_sha = Digest::SHA256.hexdigest("fake-image-bytes")
    assert_equal expected_sha, entry[:sha256]
    assert_includes entry[:local_path], expected_sha[0..1]
    assert_includes entry[:local_path], expected_sha[2..3]

    file_path = File.join(@tmp, entry[:local_path])
    assert File.exist?(file_path)
    assert_equal "fake-image-bytes", File.read(file_path)
  end

  test "dedupes by normalized URL" do
    stub_request(:get, "https://cdn.shopify.com/s/files/1/kit.jpg")
      .to_return(
        status: 200,
        body: "fake-image-bytes",
        headers: { "Content-Type" => "image/jpeg" }
      )

    @downloader.download("https://cdn.shopify.com/s/files/1/kit.jpg?v=123")
    @downloader.download("https://cdn.shopify.com/s/files/1/kit.jpg?v=456")

    assert_requested :get, "https://cdn.shopify.com/s/files/1/kit.jpg", times: 1
  end

  test "dedupes by SHA256 across different URLs" do
    stub_request(:get, "https://cdn.shopify.com/a.jpg")
      .to_return(status: 200, body: "same-content", headers: { "Content-Type" => "image/jpeg" })
    stub_request(:get, "https://cdn.shopify.com/b.jpg")
      .to_return(status: 200, body: "same-content", headers: { "Content-Type" => "image/jpeg" })

    a = @downloader.download("https://cdn.shopify.com/a.jpg")
    b = @downloader.download("https://cdn.shopify.com/b.jpg")

    assert_equal a[:sha256], b[:sha256]
    assert_equal a[:local_path], b[:local_path]

    media_dir = File.join(@tmp, "en", "media")
    files = Dir.glob("#{media_dir}/**/*").select { |f| File.file?(f) }
    assert_equal 1, files.length
  end

  test "writes manifest entries with attached_to" do
    stub_request(:get, "https://cdn.shopify.com/kit.jpg")
      .to_return(status: 200, body: "bytes", headers: { "Content-Type" => "image/jpeg" })

    @downloader.download(
      "https://cdn.shopify.com/kit.jpg",
      alt_text: "A kit",
      width: 100,
      height: 100,
      attached_to: { model: "product", slug: "pessary-kit", position: 1 }
    )
    @downloader.write_manifest!

    manifest_path = File.join(@tmp, "en", "media_manifest.json")
    assert File.exist?(manifest_path)
    manifest = JSON.parse(File.read(manifest_path))
    assert_equal 1, manifest["images"].length
    image = manifest["images"][0]
    assert_equal "A kit", image["alt_text"]
    assert_equal [{ "model" => "product", "slug" => "pessary-kit", "position" => 1 }], image["attached_to"]
  end

  test "merges attached_to when same image is used by multiple records" do
    stub_request(:get, "https://cdn.shopify.com/kit.jpg")
      .to_return(status: 200, body: "bytes", headers: { "Content-Type" => "image/jpeg" })

    @downloader.download("https://cdn.shopify.com/kit.jpg",
      attached_to: { model: "product", slug: "a", position: 1 })
    @downloader.download("https://cdn.shopify.com/kit.jpg",
      attached_to: { model: "taxon", slug: "starter-kits", position: 0 })
    @downloader.write_manifest!

    manifest = JSON.parse(File.read(File.join(@tmp, "en", "media_manifest.json")))
    assert_equal 2, manifest["images"][0]["attached_to"].length
  end
end
