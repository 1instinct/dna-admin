module Creators
  # Creates and updates a creator's product: a Spree::Product (master price, description,
  # categories, preview image and audio) plus a draft Spree::DigitalAsset (kind, manifest, files).
  #
  # Attributes (all optional on update; kind is required on create):
  #   name, description, price, kind, taxon_ids, preview_image_signed_id, preview_audio_signed_id,
  #   files: [signed_id]        files to add; a file named like one already in the draft replaces it
  #   keep_file_ids: [id]       when given, the draft's files become exactly these files (attachment
  #                             ids of this product's draft or published versions; other ids are
  #                             ignored) plus the new uploads in files; omitted, files are unchanged
  #                             apart from files and remove_file_ids
  #   remove_file_ids: [id]     attachment ids to take out of the draft
  #   manifest: Hash            the app-defined manifest (its server-owned "files" key is kept)
  #
  # File, kind and manifest changes always land in a draft asset. When the product has none (it is
  # live, or was rejected after going live), a new draft is started from the live version's files,
  # the product goes back to review_state "draft", and the live version stays what buyers get until
  # an admin approves the new one. New preview media on a live product wait for review the same way
  # (creator_pending_preview_image / _audio). Name, description, price and categories apply at once.
  #
  # price: at least Creators.min_price(currency) (0.50 by default): free products are admin-only,
  # so only a creator who is also an admin may go lower.
  #
  # Editable review states (PATCH): draft, changes_requested, approved, and rejected once live.
  # The state is checked under the product's row lock, so an edit never races a submit or a review.
  #
  # Raises Creators::ProductWriter::Invalid (with #fields) and changes nothing when the input is
  # refused.
  class ProductWriter
    class Invalid < StandardError
      attr_reader :fields

      def initialize(fields, message = nil)
        @fields = fields
        super(message || fields.values.flatten.first || 'is invalid')
      end
    end

    EDITABLE_STATES = %w[draft changes_requested approved].freeze
    SUBMITTABLE_STATES = %w[draft changes_requested].freeze

    def self.create(user, attrs)
      new(user, attrs).create
    end

    def self.update(product, attrs)
      new(product.creator, attrs).update(product)
    end

    # Whether the creator may edit the product now.
    def self.editable?(product)
      EDITABLE_STATES.include?(product.review_state) ||
        (product.review_state == 'rejected' && product.master.live_digital_asset.present?)
    end

    # Sends the product to review (review_state submitted) under its row lock. Needs a submittable
    # state and something to review: a draft with files, or, on a live product, preview media waiting
    # for review. Raises Invalid otherwise.
    def self.submit!(product)
      Spree::Product.transaction do
        Spree::Product.where(id: product.id).lock.pluck(:id)
        product.reload
        unless SUBMITTABLE_STATES.include?(product.review_state)
          raise Invalid.new({ review_state: ['cannot be submitted'] },
                            'Only a draft or a product with requested changes can be submitted')
        end

        draft = Spree::DigitalAsset.draft.where(variant_id: product.master.id).order(id: :desc).first
        unless draft&.files&.attached? || (product.master.live_digital_asset && product.creator_pending_preview?)
          raise Invalid.new({ files: ['are required'] }, 'Add files before submitting')
        end

        product.update!(review_state: 'submitted', submitted_at: Time.current, review_note: nil)
        product
      end
    end

    # Makes the blob the product's only master image. Returns the image (unsaved when invalid).
    def self.put_preview_image(product, blob)
      product.master.images.each(&:destroy!)
      image = Spree::Image.new(viewable: product.master, alt: product.name)
      image.attachment.attach(blob)
      image.save
      image
    end

    attr_reader :user, :attrs, :errors

    def initialize(user, attrs)
      @user = user
      @attrs = attrs.to_h.symbolize_keys
      @errors = Hash.new { |h, k| h[k] = [] }
    end

    def create
      errors[:kind] << 'is required' if attrs[:kind].to_s.strip.empty?
      Spree::Product.transaction do
        product = Spree::Product.new(creator_id: user.id, review_state: 'draft', available_on: nil,
                                     shipping_category: Creators.shipping_category)
        store = Spree::Store.default
        product.stores << store if product.respond_to?(:stores) && store.persisted?
        apply_details(product)
        blobs = new_blobs
        previews = preview_blobs
        save_product(product)
        check!
        apply_asset(Spree::DigitalAsset.new(variant: product.master, kind: attrs[:kind].to_s.strip, manifest: {}), blobs)
        apply_previews(product, previews, live: false)
        check!
        product
      end
    end

    def update(product)
      Spree::Product.transaction do
        Spree::Product.where(id: product.id).lock.pluck(:id)
        product.reload
        unless self.class.editable?(product)
          raise Invalid, { review_state: ["A product that is #{product.review_state.to_s.tr('_', ' ')} cannot be edited"] }
        end

        live = product.master.live_digital_asset.present?
        apply_details(product)
        previews = preview_blobs
        check!
        if asset_change?
          blobs = new_blobs
          check!
          draft, copied = working_draft(product, blobs)
          apply_asset(draft, blobs, copied)
          to_review(product)
        end
        to_review(product) if live && previews.values.any?
        save_product(product)
        apply_previews(product, previews, live: live)
        check!
        product
      end
    end

    private

    def check!
      raise Invalid, errors.to_h if errors.any?
    end

    # A live (approved, or rejected after going live) product with changes waiting goes back to draft.
    def to_review(product)
      product.review_state = 'draft' if %w[approved rejected].include?(product.review_state)
    end

    def admin?
      user.respond_to?(:has_spree_role?) && user.has_spree_role?('admin')
    end

    def asset_change?
      attrs.key?(:kind) || attrs.key?(:manifest) || keep_mode? || Array(attrs[:files]).any? ||
        Array(attrs[:remove_file_ids]).any?
    end

    # keep_file_ids given: the draft's files are replaced by the kept ones plus the new uploads.
    def keep_mode?
      attrs.key?(:keep_file_ids)
    end

    # --- details --------------------------------------------------------------------------------

    def apply_details(product)
      product.name = attrs[:name].to_s.strip if attrs.key?(:name)
      product.description = attrs[:description].to_s.strip.presence if attrs.key?(:description)
      apply_price(product) if attrs.key?(:price) || product.new_record?
      apply_taxons(product) if attrs.key?(:taxon_ids)
    end

    def apply_price(product)
      price = BigDecimal(attrs[:price].to_s.strip).round(2)
      min = admin? ? 0.to_d : Creators.min_price(product.master.currency)
      if price < min
        errors[:price] << format('must be at least %.2f', min)
      elsif price > 100_000
        errors[:price] << 'must be at most 100000'
      else
        product.price = price
      end
    rescue ArgumentError, TypeError
      errors[:price] << 'must be a number'
    end

    # Sets the product's marketplace categories. Taxons outside the marketplace (an admin's own
    # merchandising), and the marketplace taxon itself, which approval adds, stay as they are.
    def apply_taxons(product)
      ids = Array(attrs[:taxon_ids]).map { |id| Integer(id.to_s, exception: false) }
      marketplace = Creators.marketplace_taxon
      allowed = marketplace ? marketplace.self_and_descendants.pluck(:id) : []
      if ids.any?(&:nil?) || (ids - allowed).any?
        errors[:taxon_ids] << 'must be marketplace categories'
        return
      end
      current = product.taxon_ids
      kept = current - allowed
      kept << marketplace.id if marketplace && current.include?(marketplace.id)
      product.taxon_ids = (kept + ids).uniq
    end

    def save_product(product)
      return if product.save

      product.errors.to_hash.each { |field, messages| errors[field].concat(messages) }
    end

    # --- asset ----------------------------------------------------------------------------------

    # [asset, blobs to copy]: the product's draft asset, or a new (unsaved) draft started from the
    # live version, carrying the live files except those remove_file_ids names or a new file of the
    # same name replaces. The copies share the live blobs; Rails 6.1 never purges a blob that is still
    # attached (Blob before_destroy), so removing a draft file leaves the live file in place.
    #
    # With keep_file_ids, the blobs to copy are the kept files, and a saved draft loses the files
    # that are not kept.
    def working_draft(product, blobs)
      draft = Spree::DigitalAsset.draft.where(variant_id: product.master.id).order(id: :desc).first
      live = product.master.live_digital_asset
      draft ||= Spree::DigitalAsset.new(variant: product.master, kind: live&.kind || attrs[:kind].to_s.strip,
                                        manifest: (live&.manifest || {}).except('files'))
      return [draft, kept_draft_files(product, draft, blobs)] if keep_mode?
      return [draft, []] if draft.persisted? || live.nil?

      removed = Array(attrs[:remove_file_ids]).map(&:to_i)
      names = blobs.map { |blob| blob.filename.to_s }
      copied = live.files.attachments.includes(:blob).order(:id)
                   .reject { |a| removed.include?(a.id) || names.include?(a.filename.to_s) }.map(&:blob)
      [draft, copied]
    end

    # The kept blobs still to attach to the draft. Kept ids name attachments of this product's
    # draft or published versions; any other id is ignored. A new upload of the same name wins over
    # a kept file. Attachments of a saved draft that are not kept are taken out.
    def kept_draft_files(product, draft, blobs)
      ids = Array(attrs[:keep_file_ids]).filter_map { |id| Integer(id.to_s, exception: false) }
      asset_ids = Spree::DigitalAsset.where(variant_id: product.variants_including_master.with_deleted.select(:id),
                                            status: %w[draft published]).select(:id)
      names = blobs.map { |blob| blob.filename.to_s }
      kept = ActiveStorage::Attachment.includes(:blob)
                                      .where(id: ids, record_type: 'Spree::DigitalAsset', name: 'files', record_id: asset_ids)
                                      .map(&:blob).uniq(&:id).reject { |blob| names.include?(blob.filename.to_s) }
      return kept unless draft.persisted?

      kept_ids = kept.map(&:id)
      attached = draft.files.attachments.to_a
      gone = attached.reject { |attachment| kept_ids.include?(attachment.blob_id) }
      if gone.any?
        gone.each(&:purge_later)
        draft.files_attachments.reset
        draft.files_blobs.reset
      end
      present = (attached - gone).map(&:blob_id)
      kept.reject { |blob| present.include?(blob.id) }
    end

    # Applies kind, manifest and file changes and saves the asset once, so its validators see the
    # final set of files.
    def apply_asset(asset, blobs, copied = [])
      remove_files(asset, blobs) if asset.persisted? && !keep_mode?
      return if errors.any?

      asset.kind = attrs[:kind].to_s.strip if attrs.key?(:kind)
      apply_manifest(asset) if attrs.key?(:manifest)
      return if errors.any?

      attach = copied + blobs
      if attach.empty?
        asset.save!
      elsif asset.persisted?
        asset.attach_files!(attach)
      else
        # attach_files! reloads on failure, which a new record can't do.
        asset.files.attach(attach)
        asset.save!
        DigitalAssets::ChecksumJob.perform_later(asset.id)
      end
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.to_hash.each { |field, messages| errors[field].concat(messages.uniq) }
    end

    def apply_manifest(asset)
      manifest = attrs[:manifest]
      if manifest.is_a?(String)
        manifest = begin
          JSON.parse(manifest)
        rescue JSON::ParserError
          nil
        end
      end
      unless manifest.is_a?(Hash)
        errors[:manifest] << 'must be a JSON object'
        return
      end
      server_files = asset.manifest.is_a?(Hash) ? asset.manifest['files'] : nil
      manifest = manifest.deep_stringify_keys.except('files')
      manifest['files'] = server_files if server_files
      asset.manifest = manifest
    end

    def new_blobs
      Array(attrs[:files]).map(&:to_s).reject(&:empty?).filter_map do |signed_id|
        blob = ActiveStorage::Blob.find_signed(signed_id)
        if blob.nil?
          errors[:files] << 'contain an unknown upload'
          next
        end
        rule = Uploads.config.rule_for(blob.filename.to_s, blob.content_type)
        errors[:files] << "#{blob.filename} is not an allowed file type" unless rule
        errors[:files] << "#{blob.filename} is too large" if rule && blob.byte_size > rule[:max_bytes]
        blob
      end
    end

    # Takes the listed attachments, and those a new file of the same name replaces, out of a saved
    # draft. The blobs are purged later unless another asset version still uses them.
    def remove_files(asset, blobs)
      attachments = asset.files.attachments.includes(:blob).to_a
      ids = Array(attrs[:remove_file_ids]).map { |id| Integer(id.to_s, exception: false) }
      if (ids - attachments.map(&:id)).any?
        errors[:remove_file_ids] << 'must be files of this product'
        return
      end
      names = blobs.map { |blob| blob.filename.to_s }
      gone = attachments.select { |a| ids.include?(a.id) || names.include?(a.filename.to_s) }
      return if gone.empty?

      gone.each(&:purge_later)
      asset.files_attachments.reset
      asset.files_blobs.reset
    end

    # --- previews -------------------------------------------------------------------------------

    # { image:, audio: } blobs from the request (nil when not given); bad ones add errors.
    def preview_blobs
      {
        image: attrs.key?(:preview_image_signed_id) ? preview_blob(:preview_image_signed_id, %w[image]) : nil,
        audio: attrs.key?(:preview_audio_signed_id) ? preview_blob(:preview_audio_signed_id, %w[audio]) : nil
      }
    end

    # Before the product is live, previews apply at once. On a live product they wait for review.
    def apply_previews(product, previews, live:)
      image, audio = previews.values_at(:image, :audio)
      if live
        product.creator_pending_preview_image.attach(image) if image
        product.creator_pending_preview_audio.attach(audio) if audio
      else
        replace_preview_image(product, image) if image
        product.creator_preview_audio.attach(audio) if audio
      end
    end

    def preview_blob(key, kinds)
      blob = ActiveStorage::Blob.find_signed(attrs[key].to_s)
      unless blob && kinds.include?(blob.content_type.to_s.split('/').first) &&
             Uploads.config.rule_for(blob.filename.to_s, blob.content_type)
        errors[key] << "must be an uploaded #{kinds.first} file"
        return
      end
      blob
    end

    def replace_preview_image(product, blob)
      image = self.class.put_preview_image(product, blob)
      image.errors.full_messages.each { |message| errors[:preview_image_signed_id] << message }
    end
  end
end
