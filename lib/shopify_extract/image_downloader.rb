require "digest"
require "down"
require "fileutils"
require "json"
require "shopify_extract/url_normalizer"

module ShopifyExtract
  class ImageDownloader
    def initialize(base_dir:, locale:)
      @base_dir = base_dir
      @locale = locale
      @manifest_entries = {} # sha256 => entry hash
      @url_cache = {}        # normalized URL => sha256
      load_existing_manifest
    end

    def download(url, alt_text: nil, width: nil, height: nil, attached_to: nil)
      normalized = UrlNormalizer.call(url)

      if @url_cache[normalized]
        sha = @url_cache[normalized]
        entry = @manifest_entries[sha]
        append_attached_to(entry, attached_to)
        return entry
      end

      tempfile = Down.download(normalized)
      sha = Digest::SHA256.file(tempfile.path).hexdigest

      if @manifest_entries[sha]
        entry = @manifest_entries[sha]
        tempfile.close
        tempfile.unlink
      else
        ext = File.extname(normalized).downcase.sub(".", "")
        ext = "jpg" if ext.empty? || ext == "jpeg"
        local_path = File.join(@locale, "media", sha[0..1], sha[2..3], "#{sha}.#{ext}")
        target_path = File.join(@base_dir, local_path)
        FileUtils.mkdir_p(File.dirname(target_path))
        FileUtils.mv(tempfile.path, target_path)

        entry = {
          local_path: local_path,
          sha256: sha,
          original_url: normalized,
          width: width,
          height: height,
          bytes: File.size(target_path),
          content_type: tempfile.content_type || "application/octet-stream",
          alt_text: alt_text,
          attached_to: []
        }
        @manifest_entries[sha] = entry
      end

      @url_cache[normalized] = sha
      append_attached_to(entry, attached_to)
      entry
    end

    def write_manifest!
      FileUtils.mkdir_p(File.join(@base_dir, @locale))
      manifest = {
        "_meta" => {
          "locale" => @locale,
          "total_images" => @manifest_entries.size,
          "total_bytes" => @manifest_entries.values.sum { |e| e[:bytes] || 0 }
        },
        "images" => @manifest_entries.values.map { |e| e.transform_keys(&:to_s) }
      }
      File.write(manifest_path, JSON.pretty_generate(manifest))
    end

    def manifest_path
      File.join(@base_dir, @locale, "media_manifest.json")
    end

    private

    def append_attached_to(entry, attached_to)
      return if attached_to.nil?

      key = attached_to.transform_keys(&:to_s)
      entry[:attached_to] << key unless entry[:attached_to].include?(key)
    end

    def load_existing_manifest
      return unless File.exist?(manifest_path)

      data = JSON.parse(File.read(manifest_path))
      (data["images"] || []).each do |img|
        entry = img.transform_keys(&:to_sym)
        entry[:attached_to] ||= []
        @manifest_entries[entry[:sha256]] = entry
        @url_cache[entry[:original_url]] = entry[:sha256] if entry[:original_url]
      end
    end
  end
end
