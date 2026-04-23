class ContentAsset < Spree::Base
  has_one_attached :file

  validates :alt_text, length: { maximum: 255 }
  validates :tag, length: { maximum: 100 }
  validate  :file_must_be_attached
  validate  :acceptable_file

  before_validation :normalize_tag

  # Metadata sync happens after commit because ActiveStorage attaches
  # the blob in an after_commit callback — blob may not exist during
  # before_save on create.
  after_commit :sync_file_metadata, on: [:create, :update]

  VARIANTS = {
    mini:       { resize_to_fill: [48, 48] },
    small:      { resize_to_fill: [100, 100] },
    product:    { resize_to_fill: [240, 240] },
    large:      { resize_to_fill: [600, 600] },
    xl:         { resize_to_fill: [1000, 1000] },
    widescreen: { resize_to_fill: [1600, 900] },
    portrait:   { resize_to_fill: [900, 1600] },
  }.freeze

  ALLOWED_CONTENT_TYPES = %w[
    image/png image/jpeg image/webp image/gif image/svg+xml
  ].freeze

  MAX_FILE_SIZE = 10.megabytes

  # Ransack support for admin search
  self.whitelisted_ransackable_attributes = %w[alt_text original_filename tag]

  scope :tagged, ->(tag) { where(tag: tag) if tag.present? }
  scope :ordered, -> { order(created_at: :desc) }

  # Override Ransack's .search to provide simple filename/alt_text filtering.
  # Named .search to match the test interface; delegates to Ransack if called
  # with a hash (standard Ransack usage), otherwise treats the argument as a
  # plain text query.
  def self.search(query_or_params = nil, **opts)
    if query_or_params.is_a?(Hash) || query_or_params.nil?
      super
    else
      q = query_or_params.to_s
      q.present? ? where("original_filename ILIKE :q OR alt_text ILIKE :q", q: "%#{q}%") : all
    end
  end

  def normalize_tag
    self.tag = tag.to_s.strip.downcase.presence
  end

  def variant_url(size)
    return nil unless file.attached?
    spec = VARIANTS[size.to_sym]
    return nil unless spec
    Rails.application.routes.url_helpers.rails_storage_proxy_path(
      file.variant(spec)
    )
  end

  def original_url
    return nil unless file.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(file)
  end

  def all_urls
    return {} unless file.attached?
    urls = { original: original_url }
    VARIANTS.each_key { |size| urls[size] = variant_url(size) }
    urls
  end

  # Lightweight URLs for list responses (avoid N+1 on all variants)
  def thumbnail_urls
    return {} unless file.attached?
    { original: original_url, small: variant_url(:small) }
  end

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def acceptable_file
    return unless file.attached?

    unless file.blob.content_type.in?(ALLOWED_CONTENT_TYPES)
      errors.add(:file, "must be an image (PNG, JPEG, WebP, GIF, or SVG)")
    end

    if file.blob.byte_size > MAX_FILE_SIZE
      errors.add(:file, "must be less than #{MAX_FILE_SIZE / 1.megabyte}MB")
    end
  end

  def sync_file_metadata
    return unless file.attached? && file.blob&.filename.present?
    update_columns(
      original_filename: file.blob.filename.to_s,
      content_type:      file.blob.content_type,
      byte_size:         file.blob.byte_size
    )
  end
end
