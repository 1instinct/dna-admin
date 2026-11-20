require "test_helper"
require_relative "seed_ordinals"
require "minitest/mock"

# Seed files are ordinal-prefixed and collide across product lines. The trunk
# owns 000-099 and any fork owns 500-999, so a trunk seed and a fork seed can
# never share an ordinal. This test is inherited by every fork unchanged: the
# range it enforces comes from config/product_name.yml.
class SeedOrdinalTest < ActiveSupport::TestCase
  test "every numbered seed sits in this app's reserved range" do
    assert_empty SeedOrdinals.offences, SeedOrdinals.offences.join("\n")
  end

  test "the trunk owns 000-099 and a fork owns 500-999" do
    assert_equal (0..99), SeedOrdinals.range_for("generic")
    assert_equal (500..999), SeedOrdinals.range_for("acme")
  end

  test "an unnumbered seed is allowed" do
    assert_empty SeedOrdinals.scan(["db/seeds/default_static_pages.rb"])
  end

  test "a trunk seed outside 000-099 is an offence" do
    offences = SeedOrdinals.scan(["db/seeds/500_x.rb", "db/seeds/011_ok.rb"], 0..99)
    assert_equal 1, offences.size
    assert_match %r{\Adb/seeds/500_x\.rb \(ordinal 500 is outside 0\.\.99\)\z}, offences.first
  end

  test "a fork seed in 500-999 passes and a trunk-range seed fails" do
    assert_empty SeedOrdinals.scan(["db/seeds/500_x.rb", "db/seeds/999_y.rb"], 500..999)
    assert_match %r{011_app_links\.rb}, SeedOrdinals.scan(["db/seeds/011_app_links.rb"], 500..999).first
  end

  test "range boundaries are inclusive" do
    assert_empty SeedOrdinals.scan(["db/seeds/000_a.rb", "db/seeds/099_b.rb"], 0..99)
    assert_equal 2, SeedOrdinals.scan(["db/seeds/100_a.rb", "db/seeds/499_b.rb"], 0..99).size
  end

  test "this app's range follows config/product_name.yml" do
    SeedOrdinals.stub(:own_name, "acme") do
      assert_equal (500..999), SeedOrdinals.own_range
    end
  end
end
