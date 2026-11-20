require "yaml"

# Test support for the seed ordinal split (see seed_ordinal_test.rb).
#
# Seed files are ordinal-prefixed (db/seeds/011_app_links.rb) and used to
# collide across product lines. The trunk (`generic`) owns 000-099 and any
# other product owns 500-999, so a trunk seed and a fork seed never share an
# ordinal. 100-499 is unassigned. Seeds without a leading ordinal pass.
#
# Reads config/product_name.yml itself rather than going through
# ProductNameGuard, so each check can be reviewed on its own.
module SeedOrdinals
  ROOT = File.expand_path("../..", __dir__)

  TRUNK_NAME = "generic".freeze
  TRUNK_RANGE = (0..99).freeze
  FORK_RANGE = (500..999).freeze

  SEED_GLOB = "db/seeds/*.rb".freeze
  ORDINAL = /\A(\d+)_.*\.rb\z/

  module_function

  def own_name
    YAML.load_file(File.join(ROOT, "config/product_name.yml")).fetch("product_name").to_s.downcase
  end

  def range_for(product_name)
    product_name.to_s.downcase == TRUNK_NAME ? TRUNK_RANGE : FORK_RANGE
  end

  def own_range
    range_for(own_name)
  end

  def seed_paths
    Dir.glob(File.join(ROOT, SEED_GLOB)).map { |f| f.delete_prefix("#{ROOT}/") }.sort
  end

  # Returns a message for every numbered seed outside the range.
  def scan(paths, range = own_range)
    paths.filter_map do |path|
      match = ORDINAL.match(File.basename(path))
      next unless match && !range.cover?(match[1].to_i)
      "#{path} (ordinal #{match[1]} is outside #{range.first}..#{range.last})"
    end
  end

  def offences
    scan(seed_paths)
  end
end
