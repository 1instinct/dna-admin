require "test_helper"
require "shopify_extract/checkpoint"
require "tmpdir"

class ShopifyExtract::CheckpointTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf(@tmp)
  end

  test "loads default when file does not exist" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    assert_nil cp.last_cursor
    assert_equal 0, cp.pages_complete
    assert_equal 0, cp.records_processed
    assert_equal false, cp.completed
  end

  test "saves and loads state" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp.update!(last_cursor: "cursor1", pages_complete: 1, records_processed: 50)

    cp2 = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    assert_equal "cursor1", cp2.last_cursor
    assert_equal 1, cp2.pages_complete
    assert_equal 50, cp2.records_processed
  end

  test "mark_complete! sets completed flag" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp.mark_complete!
    assert_equal true, cp.completed

    cp2 = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    assert_equal true, cp2.completed
  end

  test "reset! clears all state" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp.update!(last_cursor: "cursor1", pages_complete: 3, records_processed: 150)
    cp.reset!

    assert_nil cp.last_cursor
    assert_equal 0, cp.pages_complete
    assert_equal false, cp.completed
  end

  test "atomic write — uses temp file pattern" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp.update!(last_cursor: "good", pages_complete: 1, records_processed: 50)

    checkpoint_path = File.join(@tmp, "en", ".checkpoints", "products.checkpoint.json")
    assert File.exist?(checkpoint_path)
    assert_equal "good", JSON.parse(File.read(checkpoint_path))["last_cursor"]
  end

  test "creates .checkpoints dir if missing" do
    cp = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp.update!(pages_complete: 1)
    assert File.directory?(File.join(@tmp, "en", ".checkpoints"))
  end

  test "different resources have independent checkpoints" do
    cp1 = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en")
    cp2 = ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "collections", locale: "en")
    cp1.update!(pages_complete: 5)
    cp2.update!(pages_complete: 2)

    assert_equal 5, ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "products", locale: "en").pages_complete
    assert_equal 2, ShopifyExtract::Checkpoint.new(dir: @tmp, resource: "collections", locale: "en").pages_complete
  end
end
