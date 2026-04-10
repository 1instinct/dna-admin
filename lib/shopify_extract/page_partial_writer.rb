require "fileutils"
require "json"

module ShopifyExtract
  class PagePartialWriter
    def initialize(dir:, resource:, locale:)
      @dir = dir
      @resource = resource
      @locale = locale
    end

    def write_page(page_number, records)
      FileUtils.mkdir_p(checkpoints_dir)
      path = page_path(page_number)
      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(records))
      File.rename(tmp, path)
    end

    def load_page(page_number)
      JSON.parse(File.read(page_path(page_number)))
    end

    def list_pages
      pattern = File.join(checkpoints_dir, "#{@resource}.page_*.json")
      Dir.glob(pattern).map do |p|
        p[/page_(\d+)\.json\z/, 1].to_i
      end.sort
    end

    def delete_all
      list_pages.each do |n|
        File.delete(page_path(n))
      end
    end

    private

    def checkpoints_dir
      File.join(@dir, @locale, ".checkpoints")
    end

    def page_path(page_number)
      File.join(checkpoints_dir, format("%s.page_%04d.json", @resource, page_number))
    end
  end
end
