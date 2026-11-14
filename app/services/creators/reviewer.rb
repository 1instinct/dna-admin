module Creators
  # Admin review of submitted creator products.
  #
  # - approve!: publishes the product's newest draft asset as the variant's next version, puts the
  #   product on sale (available_on = now, unless it already has a date) and adds it to the
  #   marketplace taxon. Older versions stay published; buyers get the newest.
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
        draft = Spree::DigitalAsset.draft.where(variant_id: product.master.id).order(id: :desc).first
        raise Error, 'This product has no draft files to publish' unless draft

        begin
          draft.publish!
        rescue ActiveRecord::RecordInvalid => e
          raise Error, "The draft cannot be published: #{e.record.errors.full_messages.to_sentence}"
        end
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

    def require_submitted!(product)
      raise Error, 'Only a submitted product can be reviewed' unless product.review_state == 'submitted'
    end
  end
end
