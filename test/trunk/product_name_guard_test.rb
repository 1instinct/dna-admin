require "test_helper"
require_relative "product_name_guard"
require "minitest/mock"

# Fails when another product's name appears in the trunk's scanned surface.
# The guard rejects *other* products' names and never this app's own
# (config/product_name.yml), which is what lets forks inherit it unchanged.
class ProductNameGuardTest < ActiveSupport::TestCase
  test "no other product's name appears in the scanned surface" do
    offences = ProductNameGuard.offences
    assert_empty offences, offences.join("\n")
  end

  test "it ignores this app's own product name" do
    assert_not_includes ProductNameGuard.forbidden_names, ProductNameGuard.own_name
  end

  test "it reports the file and line of an offence" do
    offences = ProductNameGuard.scan(["test/trunk/fixtures/offender.txt"])
    assert_match %r{offender\.txt:1}, offences.first
  end

  # The fixture names every known product on one line, so the reporting test
  # holds for a fork whatever its own name is.
  test "a fork is not flagged for its own name, and the guard still works for it" do
    ProductNameGuard::KNOWN_NAMES.each do |fork_name|
      ProductNameGuard.stub(:own_name, fork_name) do
        assert_not_includes ProductNameGuard.forbidden_names, fork_name
        assert_empty ProductNameGuard.lines_offending("the #{fork_name} app")
        assert_not_empty ProductNameGuard.scan(["test/trunk/fixtures/offender.txt"])
      end
    end
  end

  test "whole-word matching keeps the trunk free of false positives" do
    # Substring matching would fail 28 files on 'pol' (policy, polymorphic, ...)
    # and 1 on 'kry'. Word boundaries must yield zero.
    assert_equal 0, ProductNameGuard.files_matching("pol").size
    assert_equal 0, ProductNameGuard.files_matching("kry").size
  end

  test "it does not flag the vendor name 'instinct' as the product 'instincts'" do
    assert_empty ProductNameGuard.lines_offending("instinct_logo.png, Instinct")
    assert_not_empty ProductNameGuard.lines_offending("the instincts-admin fork")
  end
end
