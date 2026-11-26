module Reviews
  # Review status changes. Every path that publishes or unpublishes a review comes through here,
  # so stats and points stay in step.
  #
  # The rating is never an input. Automatic holds come from the text (blocked terms, links,
  # contact details), from photos waiting for approval, from the auto-publish setting being off,
  # or from customer reports; a 1-star and a 5-star review with the same text get the same
  # outcome. Rejections take a reason from Spree::Review::REJECTION_REASONS.
  module Moderation
    TEXT_FIELDS = %i[title body display_name].freeze

    module_function

    # [status, hold_reason] for a new or edited review.
    def initial_status(review, settings: Spree::ReviewSetting.current)
      return %w[pending auto_flag] if flagged_text?(review)
      return %w[pending photos] if review.photos.attached? && settings.photos_require_approval
      return %w[pending manual] unless settings.auto_publish

      ['published', nil]
    end

    def flagged_text?(review)
      TEXT_FIELDS.any? do |field|
        text = review.public_send(field).to_s
        text.present? && (!Profiles::ContentFilter.allowed?(text, mode: :words) || text.match?(Reviews::CONTACT_PATTERN))
      end
    end

    # Applies initial_status and its side effects; used by Reviews::Submit.
    def apply_initial_status!(review, settings: Spree::ReviewSetting.current)
      status, reason = initial_status(review, settings: settings)
      if status == 'published'
        publish!(review)
      else
        hold!(review, reason)
      end
    end

    def publish!(review, by: nil, now: Time.current)
      was_published = review.published?
      review.update!(status: 'published', moderation_reason: nil, moderated_by: by, moderated_at: by ? now : review.moderated_at,
                     published_at: review.published_at || now)
      after_change(review, was_published: was_published)
      Reviews::AwardPoints.call(review)
      review
    end

    def hold!(review, reason, by: nil, now: Time.current)
      raise ArgumentError, "unknown hold reason #{reason.inspect}" unless Spree::Review::HOLD_REASONS.include?(reason.to_s)

      was_published = review.published?
      review.update!(status: 'pending', moderation_reason: reason.to_s, moderated_by: by, moderated_at: by ? now : nil)
      after_change(review, was_published: was_published)
      review
    end

    def reject!(review, reason:, by:, now: Time.current)
      was_published = review.published?
      review.update!(status: 'rejected', moderation_reason: reason.to_s, moderated_by: by, moderated_at: now)
      after_change(review, was_published: was_published)
      review
    end

    def hide!(review, by:, now: Time.current)
      was_published = review.published?
      review.update!(status: 'hidden', moderated_by: by, moderated_at: now)
      after_change(review, was_published: was_published)
      review
    end

    # Moves a review between retail and wholesale (an admin correcting the order's signal).
    def change_channel!(review, channel:, by:, now: Time.current)
      review.update!(channel: channel.to_s, moderated_by: by, moderated_at: now)
      Reviews::RefreshStats.call(review.reviewable) if review.published?
      review
    end

    # Stats change when a review enters or leaves the published set, or a published one changes.
    def after_change(review, was_published:)
      return unless was_published || review.published?

      Reviews::RefreshStats.call(review.reviewable)
    end
  end
end
