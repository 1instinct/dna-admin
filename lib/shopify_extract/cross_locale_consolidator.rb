require "digest"
require "fileutils"
require "json"

module ShopifyExtract
  class CrossLocaleConsolidator
    def initialize(config:)
      @config = config
    end

    def call
      sha_locales = Hash.new { |h, k| h[k] = [] }

      @config.locales.each do |locale|
        manifest_path = File.join(@config.output_dir, locale, "media_manifest.json")
        next unless File.exist?(manifest_path)

        manifest = JSON.parse(File.read(manifest_path))
        (manifest["images"] || []).each do |img|
          sha_locales[img["sha256"]] << locale
        end
      end

      shared = sha_locales.select { |_sha, locales| locales.uniq.length >= 2 }
      shared_dir = File.join(@config.output_dir, "shared", "media")
      FileUtils.mkdir_p(shared_dir)

      shared.each do |sha, locales|
        src_locale = locales.uniq.first
        src_manifest = JSON.parse(File.read(File.join(@config.output_dir, src_locale, "media_manifest.json")))
        img = src_manifest["images"].find { |i| i["sha256"] == sha }
        next unless img

        src_path = File.join(@config.output_dir, img["local_path"])
        next unless File.exist?(src_path) || File.exist?(File.join(@config.output_dir, *new_shared_path(sha, img).split("/")))

        ext = File.extname(img["local_path"])
        dest_rel = new_shared_path(sha, img)
        dest_abs = File.join(@config.output_dir, dest_rel)

        unless File.exist?(dest_abs)
          FileUtils.mkdir_p(File.dirname(dest_abs))
          FileUtils.mv(src_path, dest_abs) if File.exist?(src_path)
        end

        locales.uniq.each do |locale|
          manifest_path = File.join(@config.output_dir, locale, "media_manifest.json")
          manifest = JSON.parse(File.read(manifest_path))
          manifest["images"].each do |i|
            next unless i["sha256"] == sha
            per_locale_path = File.join(@config.output_dir, i["local_path"])
            File.delete(per_locale_path) if File.exist?(per_locale_path) && i["local_path"] != dest_rel
            i["local_path"] = dest_rel
          end
          manifest["_meta"] ||= {}
          manifest["_meta"]["shared_count"] = (manifest["_meta"]["shared_count"] || 0) + 1
          File.write(manifest_path, JSON.pretty_generate(manifest))
        end
      end
    end

    private

    def new_shared_path(sha, img)
      ext = File.extname(img["local_path"])
      File.join("shared", "media", sha[0..1], sha[2..3], "#{sha}#{ext}")
    end
  end
end
