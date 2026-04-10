module ShopifyExtract
  module QueryLoader
    QUERIES_DIR = File.expand_path("queries", __dir__).freeze

    @cache = {}

    def self.load(name)
      @cache[name] ||= File.read(File.join(QUERIES_DIR, "#{name}.graphql")).freeze
    end

    def self.clear_cache!
      @cache = {}
    end
  end
end
