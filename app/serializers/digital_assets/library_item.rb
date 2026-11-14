module DigitalAssets
  # The library API's item hash:
  #
  #   { ownership_id, variant_id,
  #     product: { id, slug, name, image_url, creator: { handle, name } | nil },
  #     kind,
  #     asset: { id, version, byte_size, manifest, files: [{ id, filename, byte_size, content_type, md5, sha256 }] },
  #     source, granted_at, revoked_at }
  #
  # asset is the variant's live (highest published) version. DigitalAssets.config.creator_for
  # resolves the creator; it is nil by default.
  class LibraryItem
    def self.call(ownership, asset:, base_url: nil)
      new(ownership, asset, base_url).as_json
    end

    def initialize(ownership, asset, base_url)
      @ownership = ownership
      @asset = asset
      @base_url = base_url
    end

    def as_json(*)
      {
        ownership_id: @ownership.id,
        variant_id: @ownership.variant_id,
        product: product_json,
        kind: @asset&.kind,
        asset: asset_json,
        source: @ownership.source,
        granted_at: @ownership.granted_at&.iso8601,
        revoked_at: @ownership.revoked_at&.iso8601
      }
    end

    private

    def product
      @ownership.variant.product
    end

    def product_json
      {
        id: product.id,
        slug: product.slug,
        name: product.name,
        image_url: image_url,
        creator: DigitalAssets.config.creator_for&.call(product)
      }
    end

    def asset_json
      return nil unless @asset

      {
        id: @asset.id,
        version: @asset.version,
        byte_size: @asset.byte_size,
        manifest: @asset.manifest,
        files: @asset.file_entries
      }
    end

    # The variant's first image, else the product's (master) first image.
    def image_url
      image = @ownership.variant.images.first || product.master.images.first
      attachment = image&.attachment
      return nil unless attachment&.attached?

      helpers = Rails.application.routes.url_helpers
      @base_url ? helpers.rails_blob_url(attachment, host: @base_url) : helpers.rails_blob_path(attachment, only_path: true)
    end
  end
end
