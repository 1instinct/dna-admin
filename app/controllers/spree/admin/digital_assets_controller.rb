module Spree
  module Admin
    # "Digital asset" tab on a product: /admin/products/:product_id/digital_assets.
    # Lists the asset versions of the product's variants; creates a draft (variant, kind, manifest
    # as JSON, files), edits a draft (kind, manifest, add or remove files), publishes a draft as
    # the variant's next version, retires a version. Published versions are not edited in place:
    # changed files go in a new draft. Admin only (authorize_admin checks :admin on DigitalAsset).
    # Uploaded files follow Uploads.config (types and sizes).
    class DigitalAssetsController < Spree::Admin::BaseController
      before_action :load_product
      before_action :load_asset, only: %i[edit update destroy publish retire remove_file]

      def index
        @assets = Spree::DigitalAsset.where(variant_id: variant_ids).includes(:variant, files_attachments: :blob)
                                     .order(:variant_id, Arel.sql('version DESC NULLS FIRST'), id: :desc)
      end

      def new
        @asset = Spree::DigitalAsset.new(variant: @product.master, manifest: {})
      end

      def create
        @asset = Spree::DigitalAsset.new(variant_id: variant_ids.include?(asset_params[:variant_id].to_i) ? asset_params[:variant_id] : @product.master.id,
                                         kind: asset_params[:kind].to_s.strip)
        save_asset(:new, 'Draft created')
      end

      def edit; end

      def update
        return redirect_with_error('Only drafts can be edited; create a new draft instead') unless @asset.draft?

        @asset.kind = asset_params[:kind].to_s.strip if asset_params.key?(:kind)
        save_asset(:edit, 'Draft updated')
      end

      def destroy
        return redirect_with_error('Only drafts can be deleted') unless @asset.draft?

        @asset.files.purge_later
        @asset.destroy!
        flash[:success] = 'Draft deleted'
        redirect_to location
      end

      def publish
        @asset.publish!
        flash[:success] = "Published version #{@asset.version}"
        redirect_to location
      rescue ActiveRecord::RecordInvalid
        redirect_with_error(@asset.errors.full_messages.to_sentence, spree.edit_admin_product_digital_asset_url(@product, @asset))
      end

      def retire
        @asset.retire!
        flash[:success] = 'Version retired'
        redirect_to location
      end

      def remove_file
        return redirect_with_error('Only drafts can be edited; create a new draft instead') unless @asset.draft?

        @asset.remove_file!(params[:attachment_id])
        flash[:success] = 'File removed'
        redirect_to spree.edit_admin_product_digital_asset_url(@product, @asset)
      end

      private

      def model_class
        Spree::DigitalAsset
      end

      def load_product
        @product = Spree::Product.with_deleted.friendly.find(params[:product_id])
      end

      def variant_ids
        @variant_ids ||= @product.variants_including_master.pluck(:id)
      end

      def load_asset
        @asset = Spree::DigitalAsset.where(variant_id: variant_ids).find(params[:id])
      end

      def asset_params
        @asset_params ||= params.fetch(:digital_asset, {}).permit(:variant_id, :kind, :manifest, files: [])
      end

      def location
        spree.admin_product_digital_assets_url(@product)
      end

      def redirect_with_error(message, to = location)
        flash[:error] = message
        redirect_to to
      end

      # Applies the manifest JSON and new files, then saves; re-renders the form with errors.
      def save_asset(template, message)
        uploads = Array(asset_params[:files]).reject(&:blank?)
        apply_manifest
        check_uploads(uploads)
        if @asset.errors.empty? && @asset.valid?
          Spree::DigitalAsset.transaction do
            @asset.save!
            @asset.attach_files!(uploads.map { |file| blob_for(file) }) if uploads.any?
          end
          flash[:success] = message
          redirect_to spree.edit_admin_product_digital_asset_url(@product, @asset)
        else
          @manifest_text = asset_params[:manifest]
          render template, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid => e
        messages = e.record.errors.full_messages
        # A new draft was rolled back with its files: show the form for an unsaved one.
        @asset = Spree::DigitalAsset.new(@asset.attributes.slice('variant_id', 'kind', 'manifest')) if template == :new
        messages.each { |m| @asset.errors.add(:base, m) }
        @manifest_text = asset_params[:manifest]
        render template, status: :unprocessable_entity
      end

      def apply_manifest
        return unless asset_params.key?(:manifest)

        text = asset_params[:manifest].to_s.strip
        parsed = text.empty? ? {} : JSON.parse(text)
        # The server owns manifest["files"] (checksums); keep it across edits.
        parsed = parsed.merge('files' => @asset.manifest['files']) if parsed.is_a?(Hash) && @asset.manifest.is_a?(Hash) && @asset.manifest.key?('files')
        @asset.manifest = parsed
      rescue JSON::ParserError
        @asset.errors.add(:manifest, 'is not valid JSON')
      end

      def check_uploads(uploads)
        uploads.each do |file|
          name = file.original_filename.to_s
          rule = Uploads.config.rule_for(name, file.content_type)
          if rule.nil?
            @asset.errors.add(:files, "#{name}: this file type is not allowed")
          elsif file.size > rule[:max_bytes]
            @asset.errors.add(:files, "#{name}: too large (at most #{rule[:max_bytes] / 1.kilobyte} KB)")
          end
        end
      end

      def blob_for(file)
        ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename,
                                               content_type: file.content_type)
      end
    end
  end
end
