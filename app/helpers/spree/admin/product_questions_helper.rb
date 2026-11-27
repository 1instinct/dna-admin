module Spree
  module Admin
    # Labels and badges for Reviews > Questions.
    module ProductQuestionsHelper
      QUESTION_STATUS_BADGES = { 'pending' => 'badge-warning', 'published' => 'badge-success',
                                 'rejected' => 'badge-secondary' }.freeze
      QUESTION_STATUS_LABELS = { 'pending' => 'Waiting', 'published' => 'Answered', 'rejected' => 'Rejected' }.freeze

      def question_status_badge(question)
        content_tag(:span, QUESTION_STATUS_LABELS.fetch(question.status, question.status),
                    class: "badge #{QUESTION_STATUS_BADGES.fetch(question.status, 'badge-light')}")
      end

      def question_product_link(question)
        product = question.product || Spree::Product.with_deleted.find_by(id: question.product_id)
        product ? link_to(product.name, spree.edit_admin_product_path(product)) : '—'
      end
    end
  end
end
