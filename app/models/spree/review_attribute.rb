# An extra question in the review form, set up in admin: "Quality" (1-5) or "Fit" (bipolar, "Runs
# small" to "Runs large", 3 is true to size). Product attributes apply to products in their taxons
# (or every product when they have none); store attributes appear in store reviews.
module Spree
  class ReviewAttribute < Spree::Base
    self.table_name = 'spree_review_attributes'

    KINDS = %w[scale bipolar].freeze
    APPLIES_TO = %w[product store].freeze

    has_and_belongs_to_many :taxons, class_name: 'Spree::Taxon', join_table: 'spree_review_attributes_taxons',
                                     foreign_key: :review_attribute_id, association_foreign_key: :taxon_id
    acts_as_list

    validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]{1,40}\z/ }
    validates :label, presence: true, length: { maximum: 60 }
    validates :kind, inclusion: { in: KINDS }
    validates :applies_to, inclusion: { in: APPLIES_TO }
    validates :low_label, :high_label, presence: true, length: { maximum: 40 }, if: -> { kind == 'bipolar' }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :id) }

    # Active attributes asked about this product: those with no taxons, plus those sharing a taxon
    # (or an ancestor of one) with the product.
    def self.for_product(product)
      taxon_ids = product.taxons.flat_map { |taxon| taxon.self_and_ancestors.pluck(:id) }.uniq
      scoped = active.ordered.where(applies_to: 'product')
      with_taxons = joins(:taxons).where(spree_taxons: { id: taxon_ids }).select(:id)
      without_taxons = where.not(id: joins(:taxons).select(:id))
      scoped.where(id: with_taxons).or(scoped.where(id: without_taxons))
    end

    def self.for_store
      active.ordered.where(applies_to: 'store')
    end
  end
end
