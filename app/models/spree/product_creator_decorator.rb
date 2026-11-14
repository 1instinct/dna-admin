# Creator products: an ordinary Spree::Product with creator_id (the user who sells it) and a
# review state. Store products have neither. creator_preview_audio is the optional audio demo a
# creator attaches; the preview image is the master variant's first image.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module ProductCreatorDecorator
    REVIEW_STATES = %w[draft submitted approved rejected changes_requested].freeze

    def self.prepended(base)
      base.belongs_to :creator, class_name: Spree.user_class.to_s, optional: true
      base.has_one_attached :creator_preview_audio
      base.validates :review_state, inclusion: { in: REVIEW_STATES }, allow_nil: true
      base.scope :creator_products, -> { where.not(creator_id: nil) }
    end

    def creator_product?
      creator_id.present?
    end
  end
end

Spree::Product.prepend(Spree::ProductCreatorDecorator) unless Spree::Product.include?(Spree::ProductCreatorDecorator)
