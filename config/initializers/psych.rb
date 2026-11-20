# Fix for Psych::DisallowedClass errors
# Permit common classes for YAML deserialization
require 'psych'

# Whitelist classes for YAML safe_load
module Psych
  class << self
    alias_method :original_safe_load, :safe_load

    def safe_load(yaml, whitelist_classes = [], whitelist_symbols = [], aliases = false, filename = nil)
      # Add BigDecimal and other common classes to whitelist
      whitelist_classes = Array(whitelist_classes) + [BigDecimal, Symbol, Date, Time, DateTime]
      original_safe_load(yaml, whitelist_classes, whitelist_symbols, aliases, filename)
    end
  end
end
