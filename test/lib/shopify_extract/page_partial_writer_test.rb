require "test_helper"
require "shopify_extract/page_partial_writer"
require "tmpdir"

class ShopifyExtract::PagePartialWriterTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "writes page 1 to correct path" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(1, [{ name: "Product A" }, { name: "Product B" }])

    path = File.join(@tmp, "en", ".checkpoints", "products.page_0001.json")
    assert File.exist?(path)
    data = JSON.parse(File.read(path))
    assert_equal 2, data.length
    assert_equal "Product A", data[0]["name"]
  end

  test "writes page 42 with zero-padded filename" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(42, [{ name: "Product X" }])

    path = File.join(@tmp, "en", ".checkpoints", "products.page_0042.json")
    assert File.exist?(path)
  end

  test "overwrites existing page file" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(1, [{ name: "Old" }])
    writer.write_page(1, [{ name: "New" }])

    data = JSON.parse(File.read(File.join(@tmp, "en", ".checkpoints", "products.page_0001.json")))
    assert_equal "New", data[0]["name"]
  end

  test "list_pages returns sorted list of page numbers" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(3, [])
    writer.write_page(1, [])
    writer.write_page(2, [])

    assert_equal [1, 2, 3], writer.list_pages
  end

  test "load_page returns the data for a specific page" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(1, [{ name: "Product A" }])

    data = writer.load_page(1)
    assert_equal 1, data.length
    assert_equal "Product A", data[0]["name"]
  end

  test "delete_all removes all page files for this resource" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(1, [])
    writer.write_page(2, [])
    writer.delete_all

    assert_equal [], writer.list_pages
  end

  test "atomic write — uses temp file" do
    writer = ShopifyExtract::PagePartialWriter.new(dir: @tmp, resource: "products", locale: "en")
    writer.write_page(1, [{ name: "Product A" }])

    tmp_files = Dir.glob(File.join(@tmp, "en", ".checkpoints", "*.tmp"))
    assert_empty tmp_files
  end
end
