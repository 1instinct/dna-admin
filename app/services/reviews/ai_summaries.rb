module Reviews
  # The dna-admin side of AI review summaries (M7, docs/plans/2026-11-26-reviews-api-contract.md,
  # "M7 AI summaries"). dna-frontend's summarize job asks for stale products, reads each one's
  # reviews, has Claude write the summary, and stores it back here. The summary lives on the
  # product's retail Spree::ReviewStat row (ai_summary jsonb plus ai_summary_review_count and
  # ai_summary_generated_at), and is always written from retail reviews.
  #
  #   Reviews::AiSummaries.stale(limit: 10)                # => [Spree::ReviewStat, ...] (reviewable preloaded)
  #   Reviews::AiSummaries.input_for(product)              # => the reviews_for_summary JSON
  #   Reviews::AiSummaries.store!(product, attrs)          # => Spree::ReviewStat, or raises Invalid
  #   Reviews::AiSummaries.summary_json(stat)              # => the review_summary ai_summary shape
  #   Reviews::AiSummaries.request_regeneration!(product)  # the admin's Regenerate button
  #
  # "Regenerate requested" is stored without a column: a "regenerate_requested_at" key (ISO 8601
  # time) inside the ai_summary jsonb. The old summary stays live, with its generated_at, until the
  # new one replaces the whole hash (which drops the key). Spree::ReviewStat#visible_ai_summary
  # strips the key, so the storefront never sees it.
  module AiSummaries
    REGENERATE_KEY = 'regenerate_requested_at'.freeze
    # A summary goes stale after this many new written reviews, or this long.
    NEW_REVIEWS_THRESHOLD = 3
    MAX_AGE = 30.days
    LIMIT_DEFAULT = 10
    LIMIT_MAX = 25
    INPUT_REVIEWS_MAX = 2000
    DESCRIPTION_MAX = 2000
    HEADLINE_MAX = 80
    SUMMARY_MAX = 600
    LABEL_MAX = 40
    MODEL_MAX = 100
    ITEMS_MAX = 5
    FIT_CONSENSUS = %w[runs_small true_to_size runs_large].freeze

    # A PUT body that doesn't match the contract. fields: { "headline" => ["is too long ..."], ... }
    class Invalid < StandardError
      attr_reader :fields

      def initialize(fields)
        @fields = fields
        super(fields.map { |field, messages| "#{field} #{messages.first}" }.first || 'is invalid')
      end
    end

    module_function

    # Products that need a (new) summary: at least ai_summary_min_reviews published retail reviews
    # with text, not hidden by an admin, and one of: no summary yet; NEW_REVIEWS_THRESHOLD or more
    # written reviews since the last one; older than MAX_AGE; Regenerate pressed. Products without
    # a summary come first, then regenerate requests, then the oldest summaries. Empty while AI
    # summaries are switched off. Only products the public can see.
    def stale(limit: LIMIT_DEFAULT, settings: Spree::ReviewSetting.current, now: Time.current)
      return [] unless settings.ai_summary_enabled

      table = Spree::ReviewStat.quoted_table_name
      Spree::ReviewStat.
        where(reviewable_type: Spree::Product.name, scope: 'retail', ai_summary_hidden: false).
        where("#{table}.reviews_count >= ?", settings.ai_summary_min_reviews).
        where(reviewable_id: Spree::Product.publicly_visible.select(:id)).
        where(
          "#{table}.ai_summary IS NULL OR #{table}.ai_summary_generated_at IS NULL OR " \
          "#{table}.reviews_count - COALESCE(#{table}.ai_summary_review_count, 0) >= :new_reviews OR " \
          "#{table}.ai_summary_generated_at < :cutoff OR #{table}.ai_summary ->> :regenerate IS NOT NULL",
          new_reviews: NEW_REVIEWS_THRESHOLD, cutoff: now - MAX_AGE, regenerate: REGENERATE_KEY
        ).
        order(Arel.sql("(#{table}.ai_summary IS NULL) DESC")).
        order(Arel.sql(Spree::ReviewStat.sanitize_sql_array(["(#{table}.ai_summary ->> ? IS NOT NULL) DESC", REGENERATE_KEY]))).
        order(Arel.sql("#{table}.ai_summary_generated_at ASC NULLS FIRST, #{table}.id ASC")).
        limit(clamp_limit(limit)).
        preload(:reviewable).to_a
    end

    def clamp_limit(value)
      number = Integer(value.presence || LIMIT_DEFAULT, exception: false) || LIMIT_DEFAULT
      number.clamp(1, LIMIT_MAX)
    end

    def stale_json(stat)
      product = stat.reviewable
      { product_id: product.id, slug: product.slug, name: product.name, reviews_count: stat.reviews_count,
        summarized_count: stat.ai_summary.present? ? stat.ai_summary_review_count : nil,
        generated_at: stat.ai_summary.present? ? stat.ai_summary_generated_at&.utc&.iso8601 : nil }
    end

    # What the summarizer reads: the product, retail rating stats (the histogram counts star-only
    # ratings too) and up to INPUT_REVIEWS_MAX published retail reviews with text, newest first.
    def input_for(product, max_reviews: INPUT_REVIEWS_MAX)
      summary = Reviews::Presenter.new.summary(product, 'retail')
      reviews = Spree::Review.published.retail.written.where(reviewable: product).
                order(published_at: :desc, id: :desc).limit(max_reviews).
                includes(variant: { option_values: :option_type })
      {
        product: { id: product.id, slug: product.slug, name: product.name, description: plain_text(product.description, DESCRIPTION_MAX) },
        ratings_count: summary[:ratings_count],
        reviews_count: summary[:reviews_count],
        histogram: summary[:histogram],
        attributes: summary[:attributes],
        reviews: reviews.select(&:written?).map do |review|
          { id: review.id, rating: review.rating, title: review.title, body: review.body, variant_label: review.variant_label,
            attribute_ratings: review.attribute_ratings, published_at: review.published_at&.utc&.iso8601 }
        end
      }
    end

    # Validates the PUT body (a Hash parsed from JSON) and writes it to the retail ReviewStat.
    # Text has HTML stripped before its length is checked. Raises Invalid.
    def store!(product, attrs, now: Time.current)
      summary, review_count = validate!(attrs)
      stat = Spree::ReviewStat.for(product, 'retail')
      stat.update!(ai_summary: summary, ai_summary_review_count: review_count, ai_summary_generated_at: now)
      stat
    end

    # The review_summary ai_summary shape, whether or not an admin has hidden it.
    def summary_json(stat)
      return if stat.ai_summary.blank?

      stat.ai_summary.except(REGENERATE_KEY).merge(
        'review_count' => stat.ai_summary_review_count, 'generated_at' => stat.ai_summary_generated_at&.utc&.iso8601,
        'source_scope' => 'retail'
      )
    end

    # Marks an existing summary for regeneration. Returns false when there's no summary (a product
    # without one is already stale once it has enough reviews).
    def request_regeneration!(product, now: Time.current)
      stat = Spree::ReviewStat.for(product, 'retail')
      return false if stat.new_record? || stat.ai_summary.blank?

      stat.update!(ai_summary: stat.ai_summary.merge(REGENERATE_KEY => now.utc.iso8601))
      true
    end

    def regeneration_requested_at(stat)
      value = stat.ai_summary.is_a?(Hash) ? stat.ai_summary[REGENERATE_KEY] : nil
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def validate!(attrs)
      errors = Hash.new { |hash, key| hash[key] = [] }
      unless attrs.is_a?(Hash)
        errors['base'] << 'must be a JSON object'
        raise Invalid, errors
      end

      attrs = attrs.stringify_keys
      headline = text_field(attrs, 'headline', HEADLINE_MAX, errors)
      summary = text_field(attrs, 'summary', SUMMARY_MAX, errors)
      pros = items_field(attrs, 'pros', errors)
      cons = items_field(attrs, 'cons', errors)
      fit = attrs['fit_consensus']
      errors['fit_consensus'] << "must be one of #{FIT_CONSENSUS.join(', ')} or null" unless fit.nil? || FIT_CONSENSUS.include?(fit)
      review_count = attrs['review_count']
      errors['review_count'] << 'must be a whole number of at least 1' unless review_count.is_a?(Integer) && review_count >= 1
      model = attrs['model']
      if !model.nil? && !model.is_a?(String)
        errors['model'] << 'must be a string'
        model = nil
      end
      model = strip_html(model) if model
      errors['model'] << "is too long (maximum is #{MODEL_MAX} characters)" if model && model.length > MODEL_MAX
      raise Invalid, errors if errors.any?

      [{ 'headline' => headline, 'summary' => summary, 'pros' => pros, 'cons' => cons, 'fit_consensus' => fit,
         'model' => model.presence }, review_count]
    end

    def text_field(attrs, key, max, errors, label: key)
      value = attrs[key]
      unless value.is_a?(String)
        errors[label] << 'must be a string'
        return
      end

      text = strip_html(value)
      if text.empty?
        errors[label] << "can't be blank"
      elsif text.length > max
        errors[label] << "is too long (maximum is #{max} characters)"
      end
      text
    end

    def items_field(attrs, key, errors)
      items = attrs[key]
      unless items.is_a?(Array)
        errors[key] << 'must be a list'
        return []
      end
      if items.size > ITEMS_MAX
        errors[key] << "can't have more than #{ITEMS_MAX} items"
        return []
      end

      items.each_with_index.map do |item, index|
        unless item.is_a?(Hash)
          errors["#{key}[#{index}]"] << 'must be an object with label and mentions'
          next
        end

        item = item.stringify_keys
        label = text_field(item, 'label', LABEL_MAX, errors, label: "#{key}[#{index}].label")
        mentions = item['mentions']
        errors["#{key}[#{index}].mentions"] << 'must be a whole number of at least 1' unless mentions.is_a?(Integer) && mentions >= 1
        { 'label' => label, 'mentions' => mentions }
      end
    end

    # Text with tags removed and entities decoded, whitespace collapsed to single spaces.
    def strip_html(value)
      text = CGI.unescapeHTML(Rails::Html::FullSanitizer.new.sanitize(value.to_s.delete("\0")).to_s)
      text.gsub(/<[^>]*>/, '').squish
    end

    # A product description as plain text: block tags become line breaks, at most `max` characters.
    def plain_text(html, max)
      with_breaks = html.to_s.delete("\0").gsub(%r{<\s*(?:br|/p|/div|/li|/h[1-6]|/tr)\b[^>]*>}i, "\n")
      text = CGI.unescapeHTML(Rails::Html::FullSanitizer.new.sanitize(with_breaks).to_s).gsub(/<[^>]*>/, '')
      text = text.gsub(/[^\S\n]+/, ' ').gsub(/ *\n[\s]*/, "\n").strip
      text.truncate(max, separator: /\s/, omission: '…')
    end
  end
end
