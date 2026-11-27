# A shopper's question about a product. Only questions with a published answer are public, so a
# product page never shows a wall of unanswered questions; the asker is emailed when one is
# answered.
module Spree
  class ProductQuestion < Spree::Base
    self.table_name = 'spree_product_questions'

    STATUSES = %w[pending published rejected].freeze
    BODY_MIN = 10
    BODY_MAX = 500

    belongs_to :product, class_name: 'Spree::Product'
    belongs_to :user, class_name: 'Spree::User', optional: true
    has_many :answers, class_name: 'Spree::ProductAnswer', foreign_key: :question_id, inverse_of: :question,
                       dependent: :destroy

    validates :body, presence: true, length: { minimum: BODY_MIN, maximum: BODY_MAX }
    validates :display_name, presence: true, length: { maximum: Spree::Review::DISPLAY_NAME_MAX }
    validates :status, inclusion: { in: STATUSES }

    scope :published, -> { where(status: 'published') }
    scope :pending, -> { where(status: 'pending') }
    scope :answered, -> { published.where('answers_count > 0') }
    # Newest published answer first (the public order).
    scope :by_latest_answer, lambda {
      latest = Spree::ProductAnswer.published.where('spree_product_answers.question_id = spree_product_questions.id').
               select('MAX(COALESCE(spree_product_answers.published_at, spree_product_answers.created_at))')
      order(Arel.sql("(#{latest.to_sql}) DESC NULLS LAST, spree_product_questions.id DESC"))
    }

    def refresh_answers_count!
      update_columns(answers_count: answers.published.count, updated_at: Time.current)
    end
  end
end
