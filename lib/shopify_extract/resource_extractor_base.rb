require "shopify_extract/checkpoint"
require "shopify_extract/page_partial_writer"
require "shopify_extract/finalizer"
require "shopify_extract/version"

module ShopifyExtract
  class ResourceExtractorBase
    class MissingMarketError < StandardError; end

    def initialize(config:, client:, locale:, topology:, force: false)
      @config = config
      @client = client
      @locale = locale
      @topology = topology
      @force = force

      # Fail fast if this locale has no market mapping
      if @topology[:locale_to_market][@locale].nil?
        raise MissingMarketError,
              "Locale '#{@locale}' has no market mapping in topology. " \
              "Check extracted/_meta/topology.json or your Shopify Markets config."
      end
    end

    def call
      checkpoint = Checkpoint.new(dir: @config.output_dir, resource: resource_name, locale: @locale)

      final_path = File.join(@config.output_dir, @locale, "#{resource_name}.json")

      if checkpoint.completed && File.exist?(final_path) && !@force
        puts "[#{@locale}/#{resource_name}] already complete (use FORCE=1 to re-extract)"
        return
      end

      if @force
        checkpoint.reset!
        writer.delete_all
      end

      last_cursor = checkpoint.last_cursor
      page_number = checkpoint.pages_complete

      loop do
        page_number += 1
        result = fetch_page(cursor: last_cursor)
        records = result[:records].map { |r| map_record(r) }

        # Write partial BEFORE updating checkpoint so a crash between
        # write and update just re-writes the same page on resume (idempotent)
        writer.write_page(page_number, records)

        checkpoint.update!(
          last_cursor: result[:end_cursor],
          pages_complete: page_number,
          records_processed: checkpoint.records_processed + records.length
        )

        break unless result[:has_next_page]
        last_cursor = result[:end_cursor]
      end

      # Mark complete BEFORE finalize so a crash between mark and finalize
      # prevents a re-run from overwriting the good final file with empty partials.
      checkpoint.mark_complete!
      finalize!
      puts "[#{@locale}/#{resource_name}] complete: #{checkpoint.records_processed} records"
    end

    protected

    # Override in subclasses
    def resource_name
      raise NotImplementedError
    end

    def fetch_page(cursor:)
      raise NotImplementedError, "return { records: [], end_cursor: nil, has_next_page: false }"
    end

    def map_record(record)
      raise NotImplementedError
    end

    def output_key
      resource_name
    end

    private

    def writer
      @writer ||= PagePartialWriter.new(dir: @config.output_dir, resource: resource_name, locale: @locale)
    end

    def finalize!
      market = @topology[:locale_to_market][@locale] || {}
      Finalizer.new(
        dir: @config.output_dir,
        resource: resource_name,
        locale: @locale,
        store_code: "cntrl-#{@locale}",
        country_code: market["country_code"],
        currency: market["currency"],
        schema_version: ShopifyExtract::SCHEMA_VERSION,
        api_version: @config.api_version,
        output_key: output_key
      ).call
    end
  end
end
