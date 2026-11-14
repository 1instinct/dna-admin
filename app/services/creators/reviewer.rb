module Creators
  # Admin review of submitted creator products.
  #
  # - approve!: publishes the product's newest draft asset as the variant's next version and moves
  #   preview media waiting for review into place, puts the product on sale (available_on = now,
  #   unless it already has a date) and adds it to the marketplace taxon. Older versions stay
  #   published; buyers get the newest. Refused when the creator has no active account (suspended,
  #   or the role revoked) or there is nothing to publish.
  # - request_changes! / reject!: store the note (required). The draft stays as it is; a live
  #   product keeps selling its live version.
  module Reviewer
    class Error < StandardError; end

    module_function

    def approve!(product, _reviewer, note = nil)
      Spree::Product.transaction do
        Spree::Product.where(id: product.id).lock.pluck(:id)
        product.reload
        require_submitted!(product)
        raise Error, 'The creator has no active account' unless Creators.active_account(product.creator)

        draft = Spree::DigitalAsset.draft.where(variant_id: product.master.id).order(id: :desc).first
        unless draft || product.creator_pending_preview?
          raise Error, 'This product has no draft files or preview changes to publish'
        end

        begin
          draft&.publish!
        rescue ActiveRecord::RecordInvalid => e
          raise Error, "The draft cannot be published: #{e.record.errors.full_messages.to_sentence}"
        end
        publish_pending_previews!(product)
        product.available_on = Time.current if product.available_on.nil?
        marketplace = Creators.marketplace_taxon
        if marketplace
          product.taxons << marketplace unless product.taxons.include?(marketplace)
        else
          Rails.logger.warn("[creators] marketplace taxon #{Creators.config.marketplace_taxon_permalink.inspect} not found")
        end
        product.update!(review_state: 'approved', review_note: note.to_s.strip.presence)
        product
      end
    end

    def request_changes!(product, _reviewer, note)
      decide!(product, 'changes_requested', note)
    end

    def reject!(product, _reviewer, note)
      decide!(product, 'rejected', note)
    end

    def decide!(product, state, note)
      note = note.to_s.strip
      raise Error, 'A note for the creator is required' if note.empty?

      Spree::Product.transaction do
        Spree::Product.where(id: product.id).lock.pluck(:id)
        product.reload
        require_submitted!(product)
        product.update!(review_state: state, review_note: note)
        product
      end
    end

    # Moves preview media that waited for review into place: the image becomes the master image,
    # the audio the preview audio. The pending attachments are dropped (their blobs now serve the
    # live previews).
    def publish_pending_previews!(product)
      if product.creator_pending_preview_image.attached?
        image = Creators::ProductWriter.put_preview_image(product, product.creator_pending_preview_image.blob)
        unless image.persisted?
          raise Error, "The preview image cannot be published: #{image.errors.full_messages.to_sentence}"
        end

        product.creator_pending_preview_image.detach
      end
      return unless product.creator_pending_preview_audio.attached?

      product.creator_preview_audio.attach(product.creator_pending_preview_audio.blob)
      product.creator_pending_preview_audio.detach
    end

    def require_submitted!(product)
      raise Error, 'Only a submitted product can be reviewed' unless product.review_state == 'submitted'
    end
  end
end
