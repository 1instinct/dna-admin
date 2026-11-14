# A user's application to sell digital products. At most one may be pending per user (validation
# plus a unique partial index). Demo files come in as direct-upload signed ids
# (sample_upload_signed_ids=) and are attached as samples; they must pass Uploads.config.
# Creators::Approver approves or rejects; the applicant may withdraw while pending.
module Spree
  class CreatorApplication < Spree::Base
    class NotPending < StandardError; end

    STATUSES = %w[pending approved rejected withdrawn].freeze
    DISPLAY_NAME_MAX = 60
    ABOUT_MAX = 2000
    LINKS_MAX = 10
    LINK_LABEL_MAX = 60
    LINK_URL_MAX = 300

    self.table_name = 'spree_creator_applications'

    belongs_to :user, class_name: Spree.user_class.to_s
    belongs_to :reviewed_by, class_name: Spree.user_class.to_s, optional: true
    has_many_attached :samples

    scope :pending, -> { where(status: 'pending') }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    before_validation :normalize_fields
    validates :status, inclusion: { in: STATUSES }
    validates :display_name, presence: true, length: { maximum: DISPLAY_NAME_MAX }
    validates :about, length: { maximum: ABOUT_MAX }
    validates :review_note, length: { maximum: ABOUT_MAX }
    validate :one_pending_per_user
    validate :check_kinds
    validate :check_portfolio_links
    validate :check_samples

    STATUSES.each do |name|
      define_method("#{name}?") { status == name }
    end

    # Demo files as signed blob ids. Each must be an existing blob that Uploads.config allows.
    def sample_upload_signed_ids=(ids)
      ids = Array(ids).map(&:to_s).reject(&:blank?)
      @sample_errors = []
      @sample_errors << "at most #{Creators.config.max_samples} files" if ids.size > Creators.config.max_samples
      return if @sample_errors.any?

      blobs = ids.map { |id| ActiveStorage::Blob.find_signed(id) }
      if blobs.any?(&:nil?)
        @sample_errors << 'contain an unknown upload'
        return
      end
      blobs.each do |blob|
        rule = Uploads.config.rule_for(blob.filename.to_s, blob.content_type)
        if rule.nil?
          @sample_errors << "#{blob.filename} is not an allowed file type"
        elsif blob.byte_size > rule[:max_bytes]
          @sample_errors << "#{blob.filename} is too large"
        end
      end
      samples.attach(blobs) if @sample_errors.empty?
    end

    def withdraw!
      raise NotPending, 'Only a pending application can be withdrawn' unless pending?

      update!(status: 'withdrawn')
    end

    private

    def normalize_fields
      self.display_name = display_name.to_s.strip
      self.about = about.to_s.strip.presence
      self.kinds = Array(kinds).map { |kind| kind.to_s.strip }.reject(&:empty?).uniq
    end

    def one_pending_per_user
      return unless pending? && user_id

      others = self.class.pending.where(user_id: user_id)
      others = others.where.not(id: id) if persisted?
      errors.add(:base, 'You already have a pending application') if others.exists?
    end

    def check_kinds
      if kinds.empty?
        errors.add(:kinds, 'must name at least one kind')
        return
      end
      allowed = Array(DigitalAssets.config.kinds).map(&:to_s)
      unknown = allowed.empty? ? kinds.grep_v(Spree::DigitalAsset::KIND_FORMAT) : kinds - allowed
      errors.add(:kinds, "include an unknown kind: #{unknown.join(', ')}") if unknown.any?
    end

    def check_portfolio_links
      links = portfolio_links
      unless links.is_a?(Array) && links.size <= LINKS_MAX
        errors.add(:portfolio_links, "must be a list of at most #{LINKS_MAX} links")
        return
      end
      valid = links.all? do |link|
        link.is_a?(Hash) && link.keys.map(&:to_s).sort == %w[label url] && valid_label?(link['label']) && http_url?(link['url'])
      end
      errors.add(:portfolio_links, 'must be http(s) links with a label') unless valid
    end

    def valid_label?(label)
      label.is_a?(String) && label.strip.present? && label.length <= LINK_LABEL_MAX
    end

    def http_url?(url)
      return false unless url.is_a?(String) && url.length <= LINK_URL_MAX

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def check_samples
      Array(@sample_errors).each { |message| errors.add(:samples, message) }
    end
  end
end
