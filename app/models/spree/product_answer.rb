# An answer to a product question: official (written by staff in admin) or from a customer, who
# is flagged verified_buyer when they bought the product.
module Spree
  class ProductAnswer < Spree::Base
    self.table_name = 'spree_product_answers'

    STATUSES = %w[pending published rejected].freeze
    BODY_MAX = 2000

    belongs_to :question, class_name: 'Spree::ProductQuestion', inverse_of: :answers
    belongs_to :user, class_name: 'Spree::User', optional: true

    validates :body, presence: true, length: { maximum: BODY_MAX }
    validates :display_name, presence: true, length: { maximum: Spree::Review::DISPLAY_NAME_MAX }
    validates :status, inclusion: { in: STATUSES }

    scope :published, -> { where(status: 'published') }

    after_commit -> { question&.refresh_answers_count! }, on: %i[create update destroy]
  end
end
