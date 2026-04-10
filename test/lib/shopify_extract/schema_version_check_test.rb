require "test_helper"
require "shopify_extract/schema_version_check"
require "shopify_extract/version"
require "tmpdir"
require "json"

class ShopifyExtract::SchemaVersionCheckTest < ActiveSupport::TestCase
  setup { @tmp = Dir.mktmpdir }
  teardown { FileUtils.rm_rf(@tmp) }

  test "writes version file on first call" do
    ShopifyExtract::SchemaVersionCheck.new(output_dir: @tmp).call!
    path = File.join(@tmp, "_meta", "schema_version.json")
    assert File.exist?(path)
    data = JSON.parse(File.read(path))
    assert_equal ShopifyExtract::SCHEMA_VERSION, data["schema_version"]
  end

  test "passes when version matches" do
    ShopifyExtract::SchemaVersionCheck.new(output_dir: @tmp).call!
    assert_nothing_raised do
      ShopifyExtract::SchemaVersionCheck.new(output_dir: @tmp).call!
    end
  end

  test "raises when version mismatches and MIGRATE is not set" do
    FileUtils.mkdir_p(File.join(@tmp, "_meta"))
    File.write(File.join(@tmp, "_meta", "schema_version.json"), { schema_version: "0.9.0" }.to_json)

    err = assert_raises(ShopifyExtract::SchemaVersionCheck::MismatchError) do
      ShopifyExtract::SchemaVersionCheck.new(output_dir: @tmp, migrate: false).call!
    end
    assert_includes err.message, "0.9.0"
    assert_includes err.message, ShopifyExtract::SCHEMA_VERSION
    assert_includes err.message, "MIGRATE=1"
  end

  test "clears all checkpoints and partials when MIGRATE=1" do
    FileUtils.mkdir_p(File.join(@tmp, "en", ".checkpoints"))
    File.write(File.join(@tmp, "en", ".checkpoints", "products.checkpoint.json"), "{}")
    File.write(File.join(@tmp, "en", ".checkpoints", "products.page_0001.json"), "[]")
    FileUtils.mkdir_p(File.join(@tmp, "_meta"))
    File.write(File.join(@tmp, "_meta", "schema_version.json"), { schema_version: "0.9.0" }.to_json)

    ShopifyExtract::SchemaVersionCheck.new(output_dir: @tmp, migrate: true).call!

    refute File.exist?(File.join(@tmp, "en", ".checkpoints", "products.checkpoint.json"))
    refute File.exist?(File.join(@tmp, "en", ".checkpoints", "products.page_0001.json"))

    data = JSON.parse(File.read(File.join(@tmp, "_meta", "schema_version.json")))
    assert_equal ShopifyExtract::SCHEMA_VERSION, data["schema_version"]
  end
end
