module Spree
  module Admin
    # Small pieces of the Feedback tab: kind badges, rating dots, status badges.
    module AppFeedbacksHelper
      FEEDBACK_KIND_LABELS = { 'bug' => 'Bug', 'idea' => 'Idea', 'other' => 'Other', 'rating' => 'Rating' }.freeze
      FEEDBACK_KIND_BADGES = { 'bug' => 'badge-danger', 'idea' => 'badge-info', 'other' => 'badge-secondary',
                               'rating' => 'badge-warning' }.freeze
      FEEDBACK_STATUS_BADGES = { 'new' => 'badge-primary', 'triaged' => 'badge-info', 'done' => 'badge-success',
                                 'archived' => 'badge-light' }.freeze

      def feedback_kind_badge(feedback)
        content_tag(:span, FEEDBACK_KIND_LABELS.fetch(feedback.kind, feedback.kind),
                    class: "badge #{FEEDBACK_KIND_BADGES.fetch(feedback.kind, 'badge-secondary')}")
      end

      def feedback_status_badge(feedback)
        content_tag(:span, feedback.status, class: "badge #{FEEDBACK_STATUS_BADGES.fetch(feedback.status, 'badge-light')}")
      end

      # Five dots, the first `rating` filled; nothing when there's no rating.
      def feedback_rating_dots(rating)
        return ''.html_safe if rating.blank?

        dots = (1..5).map do |i|
          content_tag(:span, '', class: 'feedback-dot', style: "display:inline-block;width:8px;height:8px;margin-right:2px;" \
                                                              "border-radius:50%;border:1px solid currentColor;" \
                                                              "#{'background:currentColor;' if i <= rating}")
        end
        content_tag(:span, safe_join(dots), title: "#{rating} of 5", 'aria-label': "#{rating} of 5",
                                            class: 'text-nowrap text-warning')
      end

      def feedback_build(feedback)
        version = [feedback.app_version, feedback.build_number.presence && "(#{feedback.build_number})"].compact.join(' ')
        [feedback.platform, version.presence].compact.join(' ')
      end
    end
  end
end
