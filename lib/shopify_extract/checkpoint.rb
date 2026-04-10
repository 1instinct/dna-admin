require "fileutils"
require "json"
require "time"

module ShopifyExtract
  class Checkpoint
    attr_reader :resource, :locale, :last_cursor, :pages_complete,
                :records_processed, :records_skipped, :started_at,
                :updated_at, :completed

    def initialize(dir:, resource:, locale:)
      @base_dir = dir
      @resource = resource
      @locale = locale
      @last_cursor = nil
      @pages_complete = 0
      @records_processed = 0
      @records_skipped = 0
      @started_at = nil
      @updated_at = nil
      @completed = false
      load_from_disk
    end

    def update!(last_cursor: nil, pages_complete: nil, records_processed: nil, records_skipped: nil)
      @last_cursor = last_cursor unless last_cursor.nil?
      @pages_complete = pages_complete unless pages_complete.nil?
      @records_processed = records_processed unless records_processed.nil?
      @records_skipped = records_skipped unless records_skipped.nil?
      @started_at ||= Time.now.utc.iso8601
      @updated_at = Time.now.utc.iso8601
      persist!
    end

    def mark_complete!
      @completed = true
      @updated_at = Time.now.utc.iso8601
      persist!
    end

    def reset!
      @last_cursor = nil
      @pages_complete = 0
      @records_processed = 0
      @records_skipped = 0
      @started_at = nil
      @updated_at = nil
      @completed = false
      File.delete(path) if File.exist?(path)
    end

    def path
      File.join(@base_dir, @locale, ".checkpoints", "#{@resource}.checkpoint.json")
    end

    private

    def load_from_disk
      return unless File.exist?(path)

      data = JSON.parse(File.read(path))
      @last_cursor = data["last_cursor"]
      @pages_complete = data["pages_complete"] || 0
      @records_processed = data["records_processed"] || 0
      @records_skipped = data["records_skipped"] || 0
      @started_at = data["started_at"]
      @updated_at = data["updated_at"]
      @completed = data["completed"] || false
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(path))
      tmp_path = "#{path}.tmp"
      File.write(tmp_path, JSON.pretty_generate(to_hash))
      File.rename(tmp_path, path)
    end

    def to_hash
      {
        resource: @resource,
        locale: @locale,
        last_cursor: @last_cursor,
        pages_complete: @pages_complete,
        records_processed: @records_processed,
        records_skipped: @records_skipped,
        started_at: @started_at,
        updated_at: @updated_at,
        completed: @completed
      }
    end
  end
end
