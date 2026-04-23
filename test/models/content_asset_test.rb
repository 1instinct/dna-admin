require 'test_helper'

class ContentAssetTest < ActiveSupport::TestCase
  setup do
    @asset = build(:content_asset)
  end

  test "valid with file attached" do
    assert @asset.valid?
  end

  test "invalid without file" do
    asset = ContentAsset.new(alt_text: "No file")
    assert_not asset.valid?
    assert asset.errors[:file].any?
  end

  test "invalid with oversized file" do
    @asset.file.attach(
      io: StringIO.new("x" * (11 * 1024 * 1024)),
      filename: "huge.png",
      content_type: "image/png"
    )
    assert_not @asset.valid?
    assert @asset.errors[:file].any?
  end

  test "invalid with non-image content type" do
    @asset.file.attach(
      io: StringIO.new("not an image"),
      filename: "file.pdf",
      content_type: "application/pdf"
    )
    assert_not @asset.valid?
    assert @asset.errors[:file].any?
  end

  test "alt_text limited to 255 characters" do
    @asset.alt_text = "a" * 256
    assert_not @asset.valid?
    assert @asset.errors[:alt_text].any?
  end

  test "tag limited to 100 characters" do
    @asset.tag = "a" * 101
    assert_not @asset.valid?
    assert @asset.errors[:tag].any?
  end

  test "tag is normalized to lowercase and stripped" do
    @asset.tag = "  Homepage  "
    @asset.valid?
    assert_equal "homepage", @asset.tag
  end

  test "tagged scope filters by tag" do
    asset1 = create(:content_asset, tag: "hero")
    asset2 = create(:content_asset, tag: "footer")
    results = ContentAsset.tagged("hero")
    assert_includes results, asset1
    assert_not_includes results, asset2
  end

  test "search scope filters by filename or alt_text" do
    asset1 = create(:content_asset, alt_text: "Banner desktop", original_filename: "banner.webp")
    asset2 = create(:content_asset, alt_text: "Icon small", original_filename: "icon.png")
    results = ContentAsset.search("banner")
    assert_includes results, asset1
    assert_not_includes results, asset2
  end

  test "syncs file metadata after commit" do
    asset = create(:content_asset)
    assert_equal "test-image.png", asset.reload.original_filename
    assert_equal "image/png", asset.content_type
    assert asset.byte_size > 0
  end

  test "VARIANTS contains expected sizes" do
    expected = [:mini, :small, :product, :large, :xl, :widescreen, :portrait]
    assert_equal expected.sort, ContentAsset::VARIANTS.keys.sort
  end

  test "all_urls returns hash with original and variant keys" do
    asset = create(:content_asset)
    urls = asset.all_urls
    assert urls.key?(:original)
    assert urls.key?(:small)
    assert urls.key?(:widescreen)
  end
end
