require "yaml"

# Test support for the product-name guard (see product_name_guard_test.rb).
#
# Fails when another product's name appears in the trunk. It rejects *other*
# products' names and never this app's own, which is what lets every fork
# inherit it: each fork sets its own name in config/product_name.yml.
module ProductNameGuard
  ROOT = File.expand_path("../..", __dir__)

  # Every product admin forked from this trunk. `instinct` (singular) is the
  # vendor, not a product, and is deliberately absent.
  KNOWN_NAMES = %w[beeper allrise saltea kry pol smokey instincts smulktis jordancolon].freeze

  SCANNED_DIRS = %w[app config db/seeds test].freeze

  EXEMPT_BASENAMES = %w[Dockerfile entrypoint.sh deploy-heroku.sh setup-heroku.sh HEROKU_DEPLOYMENT.md].freeze
  EXEMPT_GLOBS = ["*.example"].freeze
  EXEMPT_PATHS = %w[
    config/product_name.yml
    test/trunk/product_name_guard.rb
    test/trunk/product_name_guard_test.rb
  ].freeze
  EXEMPT_DIRS = %w[test/trunk/fixtures/].freeze

  module_function

  def own_name
    YAML.load_file(File.join(ROOT, "config/product_name.yml")).fetch("product_name").to_s.downcase
  end

  def forbidden_names
    KNOWN_NAMES - [own_name]
  end

  # Whole-word match, case-insensitive. Substring matching would fail on
  # 'policy' / 'polymorphic' ('pol') on the day it landed. Unlike a bare \b,
  # underscore counts as a separator, so `beeper_logo.png` is still caught.
  def pattern(names = forbidden_names)
    Regexp.union(names.map { |n| /(?<![[:alnum:]])#{Regexp.escape(n)}(?![[:alnum:]])/i })
  end

  def lines_offending(text, names = forbidden_names)
    re = pattern(names)
    text.each_line.select { |l| l.match?(re) }
  end

  # Text files only: contents are scanned, filenames are not. That keeps
  # binaries such as app/assets/images/beeper_logo.png (a recorded exception,
  # referenced by Beeper's COMPANY_LOGO) out of scope, while any code that
  # *references* such a file by name is still caught.
  def surface
    SCANNED_DIRS.flat_map { |d| Dir.glob(File.join(ROOT, d, "**", "*"), File::FNM_DOTMATCH) }
               .select { |f| File.file?(f) }
               .map { |f| f.delete_prefix("#{ROOT}/") }
               .reject { |f| exempt?(f) || binary?(f) }
               .sort
  end

  def exempt?(path)
    base = File.basename(path)
    EXEMPT_BASENAMES.include?(base) ||
      EXEMPT_GLOBS.any? { |g| File.fnmatch?(g, base) } ||
      EXEMPT_PATHS.include?(path) ||
      EXEMPT_DIRS.any? { |d| path.start_with?(d) }
  end

  def binary?(path)
    File.binread(File.join(ROOT, path), 8192).to_s.include?("\0")
  end

  # Returns "path:line" for every line that names a forbidden product.
  def scan(paths, names = forbidden_names)
    re = pattern(names)
    paths.flat_map do |path|
      full = File.expand_path(path, ROOT)
      next [] if binary?(full.delete_prefix("#{ROOT}/"))
      File.foreach(full, chomp: true).each_with_index.filter_map do |line, i|
        "#{path}:#{i + 1}" if line.valid_encoding? && line.match?(re)
      end
    end
  end

  def offences
    scan(surface)
  end

  # Files in the scanned surface matching one name; used to pin the
  # no-substring-false-positive guarantee.
  def files_matching(name)
    surface.select { |f| scan([f], [name]).any? }
  end
end
