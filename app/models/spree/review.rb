# A customer's review of a product they bought, or of the store itself (reviewable is a
# Spree::Product or a Spree::Store). A rating alone is a complete review; title, body, attribute
# ratings and photos are optional.
#
# Status: pending -> published | rejected; published <-> hidden. Status changes go through
# Reviews::Moderation, which never looks at the rating (FTC 16 CFR 465.7: no suppression of
# negative reviews). Channel (retail | wholesale) comes from the order (Reviews::Channel); retail
# pages only ever show retail reviews.
module Spree
  class Review < Spree::Base
    self.table_name = 'spree_reviews'

    STATUSES = %w[pending published rejected hidden].freeze
    CHANNELS = %w[retail wholesale].freeze
    SOURCES = %w[email web account app import].freeze
    # A rejection names one of these; the same list applies at every star level.
    REJECTION_REASONS = %w[spam off_topic personal_info abusive not_about_product duplicate].freeze
    # Why a review is waiting in the queue instead of published.
    HOLD_REASONS = %w[auto_flag photos manual reported].freeze
    TITLE_MAX = 120
    BODY_MAX = 5000
    REPLY_MAX = 2000
    DISPLAY_NAME_MAX = 60
    MAX_PHOTOS = 5
    PHOTO_MAX_BYTES = 10.megabytes
    PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
    # Named sizes for the storefront (thumbnails, cards, the lightbox). EXIF is stripped.
    PHOTO_VARIANTS = {
      thumb: { resize_to_limit: [160, 160], strip: true },
      card: { resize_to_limit: [480, 480], strip: true },
      full: { resize_to_limit: [1600, 1600], strip: true }
    }.freeze
    ANONYMOUS_NAME = 'Former customer'.freeze

    belongs_to :reviewable, polymorphic: true
    belongs_to :variant, class_name: 'Spree::Variant', optional: true
    belongs_to :user, class_name: 'Spree::User', optional: true
    belongs_to :order, class_name: 'Spree::Order', optional: true
    belongs_to :line_item, class_name: 'Spree::LineItem', optional: true
    belongs_to :review_request, class_name: 'Spree::ReviewRequest', optional: true
    belongs_to :moderated_by, class_name: 'Spree::User', optional: true
    belongs_to :reply_author, class_name: 'Spree::User', optional: true
    has_many :votes, class_name: 'Spree::ReviewVote', dependent: :delete_all
    # Points paid for this review (Reviews::AwardPoints). spree_loyalty_points validates a
    # transaction against its source's other transactions, so the source needs these.
    has_many :loyalty_points_transactions, as: :source, class_name: 'Spree::LoyaltyPointsTransaction'
    has_many :loyalty_points_credit_transactions, as: :source, class_name: 'Spree::LoyaltyPointsCreditTransaction'
    has_many :loyalty_points_debit_transactions, as: :source, class_name: 'Spree::LoyaltyPointsDebitTransaction'
    has_many_attached :photos

    validates :reviewable_type, inclusion: { in: %w[Spree::Product Spree::Store] }
    validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
    validates :status, inclusion: { in: STATUSES }
    validates :channel, inclusion: { in: CHANNELS }
    validates :source, inclusion: { in: SOURCES }
    validates :moderation_reason, inclusion: { in: REJECTION_REASONS }, if: -> { status == 'rejected' }
    validates :title, length: { maximum: TITLE_MAX }
    validates :body, length: { maximum: BODY_MAX }
    validates :reply_body, length: { maximum: REPLY_MAX }
    validates :display_name, presence: true, length: { maximum: DISPLAY_NAME_MAX }
    validates :reviewable_id, uniqueness: { scope: %i[reviewable_type user_id], message: 'already has your review' },
                              if: :user_id
    validates :reviewable_id, uniqueness: { scope: %i[reviewable_type order_id], message: 'already has a review from this order' },
                              if: :order_id
    validate :attribute_ratings_shape
    validate :photos_count_type_and_size
    validate :text_without_null_bytes

    scope :published, -> { where(status: 'published') }
    scope :pending, -> { where(status: 'pending') }
    scope :retail, -> { where(channel: 'retail') }
    scope :wholesale, -> { where(channel: 'wholesale') }
    scope :written, -> { where("COALESCE(btrim(#{table_name}.body), '') <> ''") }
    scope :for_products, -> { where(reviewable_type: Spree::Product.name) }
    scope :for_store, -> { where(reviewable_type: Spree::Store.name) }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
    # retail | wholesale | all. Unknown scopes fall back to retail, the public default.
    scope :in_scope, lambda { |name|
      case name.to_s
      when 'all' then all
      when 'wholesale' then wholesale
      else retail
      end
    }

    # "Maya R." from the order's bill address, else the user's address book, else "Customer".
    def self.default_display_name(order: nil, user: nil)
      address = order&.bill_address || order&.ship_address || user&.bill_address || user&.ship_address
      first = address&.firstname.to_s.strip
      last = address&.lastname.to_s.strip
      return 'Customer' if first.empty?

      last.empty? ? first : "#{first} #{last[0].upcase}."
    end

    def published?
      status == 'published'
    end

    def written?
      body.to_s.strip.present?
    end

    def wholesale?
      channel == 'wholesale'
    end

    def product
      reviewable if reviewable_type == Spree::Product.name
    end

    # "Rose · M" from the variant's option values, nil for the master or no variant.
    def variant_label
      return if variant.nil? || variant.is_master?

      variant.option_values.sort_by { |ov| ov.option_type&.position.to_i }.map(&:presentation).join(' · ').presence
    end

    def photo_variant(photo, size)
      return unless photo.variable?

      photo.variant(PHOTO_VARIANTS.fetch(size))
    end

    private

    def attribute_ratings_shape
      return errors.add(:attribute_ratings, 'must be an object') unless attribute_ratings.is_a?(Hash)

      attribute_ratings.each do |key, value|
        unless key.to_s.match?(/\A[a-z0-9_]{1,40}\z/) && value.is_a?(Integer) && value.between?(1, 5)
          errors.add(:attribute_ratings, 'must map attribute keys to ratings from 1 to 5')
          break
        end
      end
    end

    def photos_count_type_and_size
      return unless photos.attached?

      errors.add(:photos, "can't be more than #{MAX_PHOTOS}") if photos.size > MAX_PHOTOS
      photos.each do |photo|
        blob = photo.blob
        errors.add(:photos, 'must be JPEG, PNG, WebP or HEIC images') unless PHOTO_CONTENT_TYPES.include?(blob.content_type)
        errors.add(:photos, "must each be at most #{PHOTO_MAX_BYTES / 1.megabyte} MB") if blob.byte_size > PHOTO_MAX_BYTES
      end
    end

    def text_without_null_bytes
      %i[title body display_name reply_body].each do |field|
        value = self[field]
        errors.add(field, 'contains invalid characters') if value.is_a?(String) && value.include?("\0")
      end
    end
  end
end
