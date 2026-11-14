module Spree
  module Api
    module V1
      # The signed-in user's digital library. Bearer required (401 otherwise).
      #
      #   GET  /api/v1/library                     200 { items: [LibraryItem], updated_at } | 304
      #        Active items, plus revoked ones for DigitalAssets.config.revoked_visibility_days
      #        after revoked_at. Each item carries the variant's live (highest published) asset;
      #        an ownership whose variant has no published asset is not listed. Sends an ETag
      #        (item ids, count and latest updated_at); If-None-Match answers 304 when unchanged.
      #   POST /api/v1/library/:ownership_id/links { file_ids?: [Integer] }
      #                                            200 { links: [{ file_id, url, expires_at }] }
      #        Signed storage URLs valid for DigitalAssets.config.link_ttl, for every file of the
      #        live asset or only the listed ones. 404 unless the ownership is the user's and
      #        active. 429 past DigitalAssets.config.links_rate_limit (60 a minute) per user.
      #   POST /api/v1/library/claim { variant_id } 201 LibraryItem (200 when already owned)
      #        | 422 { error } when the variant is not claimable (DigitalAssets::Claim).
      #
      # LibraryItem: see DigitalAssets::LibraryItem.
      class LibraryController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user
        before_action :set_storage_host

        def index
          ownerships = visible_ownerships.to_a
          assets = live_assets(ownerships.map(&:variant_id))
          ownerships.select! { |ownership| assets[ownership.variant_id] }

          updated_at = latest_update(ownerships, assets)
          etag = ['library', current_api_user.id, ownerships.size, ownerships.map(&:id).join(','), updated_at&.utc&.iso8601(6)]
          return unless stale?(etag: etag, template: false)

          render json: {
            items: ownerships.map { |o| DigitalAssets::LibraryItem.call(o, asset: assets[o.variant_id], base_url: request.base_url) },
            updated_at: updated_at&.iso8601
          }
        end

        def links
          rule = DigitalAssets.config.links_rate_limit
          unless DigitalAssets::RateLimit.allow?(current_api_user, :library_links, rule)
            return render_error('Too many requests. Try again later.', :too_many_requests)
          end

          ownership = Spree::DigitalOwnership.active.find_by(id: params[:ownership_id], user_id: current_api_user.id)
          asset = ownership&.variant&.live_digital_asset
          return render_not_found unless asset

          render json: { links: signed_links(asset) }
        end

        def claim
          variant = Spree::Variant.find_by(id: params[:variant_id]) if params[:variant_id].present?
          return render_error('This item cannot be claimed', :unprocessable_entity) unless DigitalAssets::Claim.claimable?(variant)

          existing = Spree::DigitalOwnership.active.exists?(user_id: current_api_user.id, variant_id: variant.id)
          ownership = Spree::DigitalOwnership.grant!(user: current_api_user, variant: variant, source: 'free')
          item = DigitalAssets::LibraryItem.call(ownership, asset: variant.live_digital_asset, base_url: request.base_url)
          render json: item, status: existing ? :ok : :created
        end

        private

        # Disk storage (development, tests) builds URLs from the request host.
        def set_storage_host
          ActiveStorage::Current.host ||= request.base_url
        end

        def visible_ownerships
          cutoff = DigitalAssets.config.revoked_visibility_days.days.ago
          Spree::DigitalOwnership.where(user_id: current_api_user.id)
                                 .where('revoked_at IS NULL OR revoked_at > ?', cutoff)
                                 .includes(variant: [:images, { product: { master: :images } }])
                                 .order(:granted_at, :id)
        end

        # { variant_id => live asset }
        def live_assets(variant_ids)
          Spree::DigitalAsset.published.where(variant_id: variant_ids).order(version: :desc)
                             .each_with_object({}) { |asset, out| out[asset.variant_id] ||= asset }
        end

        def latest_update(ownerships, assets)
          times = ownerships.map(&:updated_at)
          times += ownerships.map { |o| o.variant.product.updated_at }
          times += ownerships.map { |o| assets[o.variant_id].updated_at }
          times.compact.max
        end

        def signed_links(asset)
          attachments = asset.files.attachments.includes(:blob).order(:id)
          if params.key?(:file_ids)
            ids = Array(params[:file_ids]).map { |id| id.to_s.to_i }
            attachments = attachments.where(id: ids)
          end
          ttl = DigitalAssets.config.link_ttl
          expires_at = (Time.current + ttl).iso8601
          attachments.map do |attachment|
            blob = attachment.blob
            { file_id: attachment.id,
              url: blob.url(expires_in: ttl, disposition: :attachment, filename: blob.filename),
              expires_at: expires_at }
          end
        end
      end
    end
  end
end
