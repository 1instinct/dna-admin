module Creators
  # The creator portal's product hash:
  #
  #   { id, slug, name, description, price, currency, kind, review_state, review_note, taxon_ids,
  #     preview: { image_url, audio_url },
  #     asset: { id, version, status, manifest, files: [{ id, filename, byte_size, content_type, md5, sha256 }] } | nil,
  #     live_asset_version, sales_count, created_at, updated_at }
  #
  # asset is the version being worked on: the newest draft, else the live (highest published)
  # version. live_asset_version is what buyers get now (nil before the first approval).
  module ProductJson
    module_function

    def call(product, base_url:)
      master = product.master
      live = master.live_digital_asset
      working = Spree::DigitalAsset.draft.where(variant_id: master.id).order(id: :desc).first || live
      {
        id: product.id,
        slug: product.slug,
        name: product.name,
        description: product.description,
        price: money(master.price),
        currency: master.currency,
        kind: working&.kind,
        review_state: product.review_state,
        review_note: product.review_note,
        taxon_ids: product.taxon_ids,
        preview: { image_url: image_url(master, base_url), audio_url: blob_url(product.creator_preview_audio, base_url) },
        asset: working && asset_json(working),
        live_asset_version: live&.version,
        sales_count: sales_count(product),
        created_at: product.created_at.iso8601,
        updated_at: product.updated_at.iso8601
      }
    end

    def asset_json(asset)
      { id: asset.id, version: asset.version, status: asset.status, manifest: asset.manifest, files: asset.file_entries }
    end

    def money(amount)
      amount.nil? ? nil : amount.to_d.round(2).to_f
    end

    # Units sold, from the earnings ledger (void sales excluded).
    def sales_count(product)
      Spree::CreatorEarning.counted.joins(:line_item)
                           .where(spree_line_items: { variant_id: product.variants_including_master.select(:id) })
                           .sum('spree_line_items.quantity').to_i
    end

    def image_url(variant, base_url)
      image = variant.images.first
      blob_url(image&.attachment, base_url)
    end

    def blob_url(attachment, base_url)
      return nil unless attachment&.attached?

      Rails.application.routes.url_helpers.rails_blob_url(attachment, host: base_url)
    end
  end
end
