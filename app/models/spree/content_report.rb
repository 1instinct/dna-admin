module Spree
  # A user's report about content (a profile today; other content types later). Stores a
  # snapshot of the reported fields at report time so moderators see what was reported even
  # after it changes.
  class ContentReport < Spree::Base
    self.table_name = 'spree_content_reports'

    REASONS = %w[spam harassment hate sexual violence impersonation self_harm other].freeze
    STATUSES = %w[open actioned dismissed].freeze
    DETAILS_MAX = 500

    belongs_to :reporter, class_name: 'Spree::User', optional: true
    belongs_to :reportable, polymorphic: true
    belongs_to :resolved_by, class_name: 'Spree::User', optional: true

    validates :reason, inclusion: { in: REASONS }
    validates :status, inclusion: { in: STATUSES }
    validates :details, length: { maximum: DETAILS_MAX }
    validate :details_without_null_bytes

    scope :open_first, -> { order(Arel.sql("CASE WHEN status = 'open' THEN 0 ELSE 1 END"), created_at: :desc) }
    scope :about_profile, ->(profile) { where(reportable_type: Spree::UserProfile.name, reportable_id: profile.id) }
    scope :about_review, ->(review) { where(reportable_type: Spree::Review.name, reportable_id: review.id) }

    # Open reports on one review that send it back to moderation (Reviews::Reports).
    REVIEW_HOLD_THRESHOLD = 3

    def self.for_profile(profile, reporter:, reason:, details: nil)
      new(reporter: reporter, reportable: profile, reason: reason.to_s, details: details.to_s.strip.presence,
          snapshot: profile_snapshot(profile))
    end

    def self.for_review(review, reporter:, reason:, details: nil)
      new(reporter: reporter, reportable: review, reason: reason.to_s, details: details.to_s.strip.presence,
          snapshot: review_snapshot(review))
    end

    def self.review_snapshot(review)
      {
        'product' => review.reviewable.try(:name), 'rating' => review.rating, 'title' => review.title,
        'body' => review.body, 'display_name' => review.display_name, 'photos' => review.photos.count,
        'status' => review.status
      }
    end

    def review?
      reportable_type == Spree::Review.name
    end

    def self.profile_snapshot(profile)
      legacy_avatar_url = profile.user&.has_attribute?(:avatar_url) ? profile.user.avatar_url.presence : nil
      {
        'handle' => profile.handle,
        'name' => profile.name,
        'bio' => profile.bio,
        'website' => profile.website,
        'links' => profile.links,
        'visibility' => profile.visibility,
        'avatar' => profile.avatar.attached? || legacy_avatar_url.present?,
        'avatar_blob_id' => profile.avatar.attached? ? profile.avatar.blob.id : nil,
        'avatar_url' => legacy_avatar_url
      }
    end

    def resolve!(status:, by:, note: nil)
      update!(status: status, resolved_by: by, resolved_at: Time.current, resolution_note: note.to_s.strip.presence)
    end

    private

    def details_without_null_bytes
      errors.add(:details, 'contains invalid characters') if details.to_s.include?("\0")
    end
  end
end
