# A versioned set of files sold as a variant: sample packs, presets, shaders, whatever the app
# sells. The app defines the kinds and each kind's manifest schema (DigitalAssets.config).
#
# A draft has no version. publish! gives it the variant's next version (max + 1); older published
# versions stay published, and the variant's live asset is the highest published version.
#
# Files are ActiveStorage attachments. Each blob's checksum is its base64 MD5; the SHA-256 of each
# file is computed after upload (DigitalAssets::ChecksumJob) and kept in manifest["files"].
module Spree
  class DigitalAsset < Spree::Base
    STATUSES = %w[draft published retired].freeze
    KIND_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,39}\z/.freeze

    self.table_name = 'spree_digital_assets'

    enum status: STATUSES.index_with(&:itself)

    belongs_to :variant, class_name: 'Spree::Variant', inverse_of: :digital_assets, touch: true
    has_many_attached :files

    before_validation :compute_byte_size
    validates :kind, presence: true, format: { with: KIND_FORMAT, allow_blank: true }
    validates :version, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
    validate :check_kind
    validate :check_manifest
    validate :check_files
    validate :check_published_has_files

    # Gives a draft the variant's next version and publishes it. Raises RecordInvalid when the asset
    # is invalid or has no files. Publishing a published asset changes nothing.
    def publish!
      return self if published?

      transaction do
        Spree::Variant.where(id: variant_id).lock.pluck(:id)
        next_version = self.class.where(variant_id: variant_id).maximum(:version).to_i + 1
        update!(status: 'published', version: next_version)
      end
      self
    end

    def retire!
      update!(status: 'retired')
    end

    # Attaches blobs (or signed blob ids), refreshes byte_size and queues the SHA-256 job.
    # Raises RecordInvalid (and attaches nothing) when the result is invalid.
    def attach_files!(blobs)
      blobs = Array(blobs).map { |b| b.is_a?(ActiveStorage::Blob) ? b : ActiveStorage::Blob.find_signed!(b) }
      transaction do
        files.attach(blobs)
        save!
      end
      DigitalAssets::ChecksumJob.perform_later(id)
      self
    rescue ActiveRecord::RecordInvalid
      reload
      raise
    end

    # Removes one file by attachment id.
    def remove_file!(attachment_id)
      files.attachments.find(attachment_id).purge_later
      reload
      save!
    end

    # [{ id, filename, byte_size, content_type, md5, sha256 }], id being the attachment id.
    def file_entries
      sha = Array(manifest.is_a?(Hash) ? manifest['files'] : nil).each_with_object({}) do |entry, out|
        out[entry['id']] = entry['sha256'] if entry.is_a?(Hash)
      end
      files.attachments.includes(:blob).order(:id).map do |file|
        { id: file.id, filename: file.filename.to_s, byte_size: file.byte_size, content_type: file.content_type,
          md5: file.checksum, sha256: sha[file.id] }
      end
    end

    # Computes the SHA-256 of every file that has none yet and stores the list in manifest["files"].
    # Entries for removed files are dropped. Touches updated_at so library ETags change.
    def store_checksums!
      known = Array(manifest['files']).select { |e| e.is_a?(Hash) }.index_by { |e| e['id'] }
      entries = files.attachments.includes(:blob).order(:id).map do |file|
        sha = known.dig(file.id, 'sha256') || sha256_of(file.blob)
        { 'id' => file.id, 'filename' => file.filename.to_s, 'sha256' => sha }
      end
      return if entries == manifest['files']

      update_columns(manifest: manifest.merge('files' => entries), updated_at: Time.current)
    end

    private

    def sha256_of(blob)
      digest = Digest::SHA256.new
      blob.download { |chunk| digest << chunk }
      digest.hexdigest
    end

    def compute_byte_size
      self.byte_size = files.attachments.sum { |a| a.blob&.byte_size.to_i }
    end

    def check_kind
      kinds = Array(DigitalAssets.config.kinds).map(&:to_s)
      return if kinds.empty? || kind.blank? || kinds.include?(kind)

      errors.add(:kind, "must be one of #{kinds.join(', ')}")
    end

    def check_manifest
      unless manifest.is_a?(Hash)
        errors.add(:manifest, 'must be a JSON object')
        return
      end

      validator = DigitalAssets.config.manifest_validators[kind] || DigitalAssets.config.manifest_validators[kind.to_s.to_sym]
      return unless validator

      args = validator.respond_to?(:arity) && validator.arity == 1 ? [manifest] : [manifest, self]
      Array(validator.call(*args)).each { |message| errors.add(:manifest, message.to_s) }
    end

    def check_files
      names = files.attachments.map { |a| a.blob&.filename.to_s }
      dupes = names.select { |n| names.count(n) > 1 }.uniq
      errors.add(:files, "have duplicate names: #{dupes.join(', ')}") if dupes.any?
      max = DigitalAssets.config.max_asset_bytes
      errors.add(:files, "must total at most #{max / 1.megabyte} MB") if max && byte_size.to_i > max
    end

    def check_published_has_files
      errors.add(:files, 'are required to publish') if published? && files.attachments.empty?
    end
  end
end
