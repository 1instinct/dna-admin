require "fileutils"
require "json"
require "time"
require "shopify_extract/version"

module ShopifyExtract
  class SchemaVersionCheck
    class MismatchError < StandardError; end

    def initialize(output_dir:, migrate: false)
      @output_dir = output_dir
      @migrate = migrate
    end

    def call!
      existing = read_existing_version

      if existing && existing != SCHEMA_VERSION
        if @migrate
          clear_all_checkpoints_and_partials!
        else
          raise MismatchError,
                "Schema version mismatch: extracted/ has #{existing}, extractor is #{SCHEMA_VERSION}. " \
                "Run with MIGRATE=1 to reset and re-extract."
        end
      end

      write_current_version
    end

    private

    def version_path
      File.join(@output_dir, "_meta", "schema_version.json")
    end

    def read_existing_version
      return nil unless File.exist?(version_path)
      JSON.parse(File.read(version_path))["schema_version"]
    rescue JSON::ParserError
      nil
    end

    def write_current_version
      FileUtils.mkdir_p(File.dirname(version_path))
      File.write(version_path, JSON.pretty_generate(
        schema_version: SCHEMA_VERSION,
        generated_at: Time.now.utc.iso8601
      ))
    end

    def clear_all_checkpoints_and_partials!
      Dir.glob(File.join(@output_dir, "*", ".checkpoints")).each do |dir|
        FileUtils.rm_rf(dir)
      end
    end
  end
end
