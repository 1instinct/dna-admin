require "test_helper"
require_relative "seed_ordinals"
require "minitest/mock"
require "tempfile"

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

  test "own_name and own_range are read from the config file" do
    {"acme" => 500..999, "generic" => 0..99}.each do |name, range|
      Tempfile.create(["product_name", ".yml"]) do |f|
        f.write("product_name: #{name}\n")
        f.flush
        SeedOrdinals.stub(:config_path, f.path) do
          assert_equal name, SeedOrdinals.own_name
          assert_equal range, SeedOrdinals.own_range
        end
      end
    end
  end

  test "own_name matches the real config/product_name.yml" do
    expected = YAML.load_file(Rails.root.join("config/product_name.yml")).fetch("product_name").to_s.downcase
    assert_equal expected, SeedOrdinals.own_name
  end
end
