require "shopify_extract/config"
require "shopify_extract/client/graphql_client"
require "shopify_extract/client/rest_client"
require "shopify_extract/scope_verifier"
require "shopify_extract/schema_version_check"
require "shopify_extract/topology_resolver"
require "shopify_extract/resources/products_extractor"
require "shopify_extract/resources/collections_extractor"
require "shopify_extract/resources/menus_extractor"
require "shopify_extract/resources/media_extractor"
require "shopify_extract/cross_locale_consolidator"

module ShopifyExtract
  class Extractor
    def initialize
      @config = Rails.application.config.shopify_extract
      raise "ShopifyExtract not configured. Set SHOPIFY_ACCESS_TOKEN." if @config.nil?

      @graphql = Client::GraphqlClient.new(@config)
      @rest = Client::RestClient.new(@config)
    end

    def call(resource: nil, locale: nil, force: false, migrate: false)
      SchemaVersionCheck.new(output_dir: @config.output_dir, migrate: migrate).call!
      verify_scopes!
      topology = resolve_topology

      locales = locale ? [locale] : @config.locales
      locales.each do |loc|
        extract_locale(loc, topology: topology, resource: resource, force: force)
      end

      if resource.nil? || resource == "media"
        CrossLocaleConsolidator.new(config: @config).call
      end
    end

    private

    def verify_scopes!
      ScopeVerifier.new(@graphql).call
    end

    def resolve_topology
      TopologyResolver.new(@graphql, output_dir: @config.output_dir).call
    end

    def extract_locale(locale, topology:, resource:, force:)
      resource_plan(resource).each do |name|
        klass = resource_class(name)
        puts "[#{locale}/#{name}] starting..."
        klass.new(config: @config, client: @graphql, locale: locale, topology: topology, force: force).call
      end

      if resource.nil? || resource == "media"
        puts "[#{locale}/media] starting..."
        Resources::MediaExtractor.new(config: @config, locale: locale).call
      end
    end

    def resource_plan(resource)
      if resource && resource != "media"
        [resource]
      elsif resource == "media"
        []
      else
        %w[collections products menus]
      end
    end

    def resource_class(name)
      {
        "collections" => Resources::CollectionsExtractor,
        "products" => Resources::ProductsExtractor,
        "menus" => Resources::MenusExtractor
      }.fetch(name) { raise "Unknown resource: #{name}" }
    end
  end
end
