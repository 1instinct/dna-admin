module Spree
  module Admin
    # The product "Reviews" tab: scope tabs, histogram rows and attribute averages. Stars, status
    # badges and excerpts come from Spree::Admin::ReviewsHelper (the moderation queue's helper).
    module ProductReviewsHelper
      PRODUCT_REVIEW_SCOPE_LABELS = { 'retail' => 'Retail', 'wholesale' => 'Wholesale', 'all' => 'All channels' }.freeze
      PRODUCT_REVIEW_CHANNEL_LABELS = { 'retail' => 'Retail', 'wholesale' => 'Wholesale' }.freeze

      # [[stars, count, percent of ratings], ...] from 5 stars down to 1.
      def product_review_histogram_rows(stat)
        counts = stat.histogram_counts
        total = counts.values.sum
        5.downto(1).map do |stars|
          count = counts[stars]
          [stars, count, total.zero? ? 0 : (count * 100.0 / total).round]
        end
      end

      def product_review_average(stat)
        format('%.2f', stat.average.to_f)
      end

      def product_review_channel_label(review)
        PRODUCT_REVIEW_CHANNEL_LABELS.fetch(review.channel, review.channel)
      end

      # [{ key:, label:, attribute:, average:, count: }, ...] in the admin's question order; keys with
      # no matching question (deleted before answers existed, or imported) come last under their key.
      def product_review_attribute_rows(stat, attributes_by_key)
        rows = stat.attribute_averages.map do |key, values|
          attribute = attributes_by_key[key]
          { key: key, label: attribute&.label || key, attribute: attribute,
            average: values['average'].to_f, count: values['count'].to_i }
        end
        rows.sort_by { |row| [row[:attribute] ? 0 : 1, row[:attribute]&.position.to_i, row[:label]] }
      end

      # "Leans Runs small" for a bipolar question; nil for a 1-5 scale.
      def product_review_bipolar_note(attribute, average)
        return unless attribute&.bipolar?

        if average < 2.75
          "Leans “#{attribute.low_label}”"
        elsif average > 3.25
          "Leans “#{attribute.high_label}”"
        else
          'Balanced (3 is the middle)'
        end
      end

      def product_review_ai_items(summary, key)
        Array(summary && summary[key]).select { |item| item.is_a?(Hash) && item['label'].present? }
      end
    end
  end
end
