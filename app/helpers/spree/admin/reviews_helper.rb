module Spree
  module Admin
    # Labels and badges for the Reviews admin (queue and detail page).
    module ReviewsHelper
      REVIEW_STATUS_BADGES = { 'pending' => 'badge-warning', 'published' => 'badge-success', 'rejected' => 'badge-secondary',
                               'hidden' => 'badge-dark' }.freeze
      REVIEW_STATUS_LABELS = { 'pending' => 'Waiting', 'published' => 'Live', 'rejected' => 'Rejected',
                               'hidden' => 'Hidden' }.freeze
      REVIEW_HOLD_LABELS = {
        'auto_flag' => 'Has a link, contact details or a blocked word',
        'photos' => 'Photos waiting for approval',
        'manual' => 'Needs a person (auto-publish off, or edited after a rejection)',
        'reported' => 'Reported by customers'
      }.freeze
      REVIEW_REJECTION_LABELS = {
        'spam' => 'Spam or advertising', 'off_topic' => 'Off-topic', 'personal_info' => 'Personal information',
        'abusive' => 'Abusive or hateful', 'not_about_product' => 'Not about the product', 'duplicate' => 'Duplicate'
      }.freeze

      def review_status_badge(review)
        content_tag(:span, REVIEW_STATUS_LABELS.fetch(review.status, review.status),
                    class: "badge #{REVIEW_STATUS_BADGES.fetch(review.status, 'badge-light')}")
      end

      def review_channel_badge(review)
        return ''.html_safe unless review.wholesale?

        content_tag(:span, 'Wholesale', class: 'badge badge-info')
      end

      # Why the review is waiting, or why it was rejected; nil otherwise.
      def review_reason_text(review)
        case review.status
        when 'pending' then REVIEW_HOLD_LABELS[review.moderation_reason]
        when 'rejected' then REVIEW_REJECTION_LABELS.fetch(review.moderation_reason, review.moderation_reason)
        end
      end

      def review_stars(rating)
        filled = '★' * rating.to_i
        empty = '☆' * (5 - rating.to_i)
        content_tag(:span, "#{filled}#{empty}", class: 'text-warning text-nowrap', title: "#{rating} of 5",
                                                 'aria-label': "#{rating} of 5")
      end

      def review_subject(review)
        if review.product
          link_to review.product.name, spree.edit_admin_product_path(review.product)
        else
          'The store'
        end
      end

      def review_excerpt(review, length: 140)
        text = [review.title, review.body].compact.join(' — ')
        text.present? ? truncate(text, length: length) : content_tag(:em, 'Rating only', class: 'text-muted')
      end

      def review_rejection_options
        REVIEW_REJECTION_LABELS.map { |key, label| [label, key] }
      end

      def review_photo_thumb(review, attachment)
        variant = review.photo_variant(attachment, :thumb)
        variant ? image_tag(main_app.url_for(variant), alt: 'Customer photo', size: '64x64', class: 'rounded border', style: 'object-fit:cover') : ''
      end
    end
  end
end
