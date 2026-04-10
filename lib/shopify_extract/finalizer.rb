require "json"
require "time"
require "shopify_extract/page_partial_writer"

module ShopifyExtract
  class Finalizer
    def initialize(dir:, resource:, locale:, store_code:, country_code:, currency:,
                   schema_version:, api_version:, output_key: nil, keep_partials: false)
      @dir = dir
      @resource = resource
      @locale = locale
      @store_code = store_code
      @country_code = country_code
      @currency = currency
      @schema_version = schema_version
      @api_version = api_version
      @output_key = output_key || resource
      @keep_partials = keep_partials
    end

    def call
      writer = PagePartialWriter.new(dir: @dir, resource: @resource, locale: @locale)
      all_records = writer.list_pages.flat_map { |n| writer.load_page(n) }

      output = {
        "_meta" => {
          "extracted_at" => Time.now.utc.iso8601,
          "locale" => @locale,
          "store_code" => @store_code,
          "country_code" => @country_code,
          "currency" => @currency,
          "count" => all_records.length,
          "api_version" => @api_version,
          "schema_version" => @schema_version
        },
        @output_key => all_records
      }

      final_path = File.join(@dir, @locale, "#{@resource}.json")
      FileUtils.mkdir_p(File.dirname(final_path))
      tmp = "#{final_path}.tmp"
      File.write(tmp, JSON.pretty_generate(output))
      File.rename(tmp, final_path)

      writer.delete_all unless @keep_partials
      final_path
    end
  end
end
