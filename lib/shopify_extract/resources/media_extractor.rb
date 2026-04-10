require "json"
require "fileutils"
require "shopify_extract/image_downloader"

module ShopifyExtract
  module Resources
    class MediaExtractor
      def initialize(config:, locale:)
        @config = config
        @locale = locale
        @downloader = ImageDownloader.new(base_dir: @config.output_dir, locale: @locale)
      end

      def call
        extract_from("products.json", "products", "slug")
        extract_from("collections.json", "taxonomies", "code")
        @downloader.write_manifest!
      end

      private

      def extract_from(file, key, slug_field)
        path = File.join(@config.output_dir, @locale, file)
        return unless File.exist?(path)

        data = JSON.parse(File.read(path))
        records = data[key] || []

        records.each do |record|
          (record["images"] || []).each_with_index do |img, idx|
            next unless img["original_url"]

            entry = @downloader.download(
              img["original_url"],
              alt_text: img["alt_text"],
              width: img["width"],
              height: img["height"],
              attached_to: { model: singularize(key), slug: record[slug_field], position: idx + 1 }
            )
            img["local_path"] = entry[:local_path]
          end
        end

        tmp_path = "#{path}.tmp"
        File.write(tmp_path, JSON.pretty_generate(data))
        File.rename(tmp_path, path)
      end

      def singularize(key)
        case key
        when "products" then "product"
        when "taxonomies" then "taxon"
        else key.sub(/s\z/, "")
        end
      end
    end
  end
end
