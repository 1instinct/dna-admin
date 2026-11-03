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
    validate :within_rate_limit, on: :create

    scope :open_first, -> { order(Arel.sql("CASE WHEN status = 'open' THEN 0 ELSE 1 END"), created_at: :desc) }
    scope :about_profile, ->(profile) { where(reportable_type: Spree::UserProfile.name, reportable_id: profile.id) }

    def self.for_profile(profile, reporter:, reason:, details: nil)
      new(reporter: reporter, reportable: profile, reason: reason.to_s, details: details.to_s.strip.presence,
          snapshot: profile_snapshot(profile))
    end

    def self.profile_snapshot(profile)
      {
        'handle' => profile.handle,
        'name' => profile.name,
        'bio' => profile.bio,
        'website' => profile.website,
        'links' => profile.links,
        'visibility' => profile.visibility,
        'avatar' => profile.avatar.attached?,
        'avatar_blob_id' => profile.avatar.attached? ? profile.avatar.blob.id : nil
      }
    end

    def rate_limited?
      errors.of_kind?(:base, :rate_limited)
    end

    def resolve!(status:, by:, note: nil)
      update!(status: status, resolved_by: by, resolved_at: Time.current, resolution_note: note.to_s.strip.presence)
    end

    private

    def within_rate_limit
      return unless reporter_id

      config = Profiles.config
      recent = self.class.where(reporter_id: reporter_id).where('created_at > ?', config.report_window.ago).count
      errors.add(:base, :rate_limited, message: 'Too many reports. Try again later.') if recent >= config.report_limit
    end
  end
end
