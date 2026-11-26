module Spree
  module Admin
    # The "Review questions" admin (Spree::ReviewAttribute): labels and the taxon picker.
    module ReviewAttributesHelper
      REVIEW_ATTRIBUTE_KIND_LABELS = { 'scale' => '1 to 5 scale', 'bipolar' => 'Two-ended scale' }.freeze
      REVIEW_ATTRIBUTE_APPLIES_TO_LABELS = { 'product' => 'Product reviews', 'store' => 'Store reviews' }.freeze

      def review_attribute_kind_options
        Spree::ReviewAttribute::KINDS.map { |kind| [REVIEW_ATTRIBUTE_KIND_LABELS.fetch(kind, kind), kind] }
      end

      def review_attribute_applies_to_options
        Spree::ReviewAttribute::APPLIES_TO.map { |value| [REVIEW_ATTRIBUTE_APPLIES_TO_LABELS.fetch(value, value), value] }
      end

      def review_attribute_kind_label(attribute)
        label = REVIEW_ATTRIBUTE_KIND_LABELS.fetch(attribute.kind, attribute.kind)
        attribute.bipolar? ? "#{label}: #{attribute.low_label} to #{attribute.high_label}" : label
      end

      # Taxons as [["Categories -> Tops -> Knits", id], ...], the same names as Spree's Taxon#pretty_name,
      # built from one query instead of an ancestors query per taxon.
      def review_attribute_taxon_options
        taxons = Spree::Taxon.order(:taxonomy_id, :lft).to_a
        by_id = taxons.index_by(&:id)
        taxons.map do |taxon|
          chain = []
          node = taxon
          while node
            chain.unshift(node.name)
            node = by_id[node.parent_id]
          end
          [chain.join(' -> '), taxon.id]
        end
      end

      def review_attribute_taxon_names(attribute)
        names = attribute.taxons.map(&:name)
        names.any? ? names.join(', ') : content_tag(:span, 'Every product', class: 'text-muted')
      end
    end
  end
end
