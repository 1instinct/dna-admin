module Reviews
  # JSON for the public review endpoints (docs/plans/2026-11-26-reviews-api-contract.md). Never
  # includes who the reviewer is beyond their display name: no user id, email or order.
  #
  #   presenter = Reviews::Presenter.new(base_url: Reviews.asset_base_url(request))
  #   presenter.review(review)
  #   presenter.summary(product, scope)
  class Presenter
    LATEST_PHOTOS = 12
    PHOTO_SIZES = %i[thumb card full].freeze

    attr_reader :base_url

    def initialize(base_url: nil)
      @base_url = base_url
    end

    def review(review)
      {
        id: review.id,
        rating: review.rating,
        title: review.title,
        body: review.body,
        display_name: review.display_name,
        variant_label: review.variant_label,
        verified_purchase: review.verified_purchase,
        incentivized: review.incentivized,
        channel: review.channel,
        attribute_ratings: review.attribute_ratings,
        photos: review.photos.map { |photo| photo(photo, review) },
        helpful_count: review.helpful_count,
        unhelpful_count: review.unhelpful_count,
        reply: reply(review),
        published_at: review.published_at&.utc&.iso8601,
        edited: review.edited_at.present?
      }
    end

    def summary(reviewable, scope)
      stat = Spree::ReviewStat.for(reviewable, scope)
      {
        scope: scope,
        average: stat.average.to_f,
        ratings_count: stat.ratings_count,
        reviews_count: stat.reviews_count,
        photos_count: stat.photos_count,
        histogram: stat.histogram_counts.transform_keys(&:to_s),
        attributes: attributes(reviewable, stat),
        ai_summary: ai_summary(reviewable, scope),
        latest_photos: latest_photos(reviewable, scope)
      }
    end

    STATUS_MESSAGES = {
      'published' => 'Your review is live.',
      'pending' => "Thanks! We're checking it before it goes live.",
      'rejected' => "This review isn't shown on the site.",
      'hidden' => "This review isn't shown on the site."
    }.freeze

    # The customer's own review: the public shape plus status and points. Never names a moderation
    # reason.
    def own_review(review, settings: Spree::ReviewSetting.current)
      review(review).merge(
        status: review.status,
        status_message: STATUS_MESSAGES.fetch(review.status),
        product: review.product && product(review.product),
        points: points(review, settings)
      )
    end

    def product(product)
      { id: product.id, slug: product.slug, name: product.name, image_url: product_image(product) }
    end

    def question(attribute)
      { key: attribute.key, label: attribute.label, kind: attribute.kind, low_label: attribute.low_label,
        high_label: attribute.high_label }
    end

    def points_offer(settings = Spree::ReviewSetting.current)
      { per_review: settings.points_per_review, photo_bonus: settings.points_photo_bonus }
    end

    # What the composer enforces: photo count, size and types, text lengths.
    def limits
      { max_photos: Spree::Review::MAX_PHOTOS, max_photo_mb: Spree::Review::PHOTO_MAX_BYTES / 1.megabyte,
        title_max: Spree::Review::TITLE_MAX, body_max: Spree::Review::BODY_MAX,
        photo_types: Spree::Review::PHOTO_CONTENT_TYPES }
    end

    def photo(attachment, review)
      urls = PHOTO_SIZES.to_h { |size| [:"#{size}_url", variant_url(review.photo_variant(attachment, size))] }
      { id: attachment.id, **urls, alt: "Customer photo of #{review.reviewable.try(:name) || 'this product'}" }
    end

    private

    def reply(review)
      return if review.reply_body.blank?

      { body: review.reply_body, replied_at: review.replied_at&.utc&.iso8601 }
    end

    # The questions asked about this product that someone has answered, in admin order.
    def attributes(reviewable, stat)
      definitions = reviewable.is_a?(Spree::Product) ? Spree::ReviewAttribute.for_product(reviewable) : Spree::ReviewAttribute.for_store
      definitions.filter_map do |definition|
        averages = stat.attribute_averages[definition.key]
        next if averages.nil? || averages['count'].to_i.zero?

        { key: definition.key, label: definition.label, kind: definition.kind, low_label: definition.low_label,
          high_label: definition.high_label, average: averages['average'].to_f, count: averages['count'].to_i }
      end
    end

    # Always the retail summary, and none for the wholesale-only scope.
    def ai_summary(reviewable, scope)
      return if scope == 'wholesale'

      stat = Spree::ReviewStat.for(reviewable, 'retail')
      summary = stat.visible_ai_summary
      return unless summary

      summary.merge('review_count' => stat.ai_summary_review_count,
                    'generated_at' => stat.ai_summary_generated_at&.utc&.iso8601, 'source_scope' => 'retail')
    end

    def latest_photos(reviewable, scope)
      reviews = Spree::Review.published.where(reviewable: reviewable).in_scope(scope)
      attachments = ActiveStorage::Attachment.where(record_type: Spree::Review.name, name: 'photos', record_id: reviews.select(:id)).
                    includes(:blob).order(created_at: :desc, id: :desc).limit(LATEST_PHOTOS)
      by_id = Spree::Review.where(id: attachments.map(&:record_id)).index_by(&:id)
      attachments.map { |attachment| photo(attachment, by_id.fetch(attachment.record_id)).merge(review_id: attachment.record_id) }
    end

    def points(review, settings)
      awarded = review.loyalty_points_credit_transactions.sum(:loyalty_points)
      pending = if review.points_awarded_at.nil? && Reviews::AwardPoints.offered?(review.user, review.reviewable, settings: settings) &&
                   %w[pending published].include?(review.status)
                  Reviews::AwardPoints.points_for(review, settings)
                else
                  0
                end
      { awarded: awarded, pending: pending }
    end

    def product_image(product)
      image = product.master.images.first || product.variant_images.first
      return unless image&.attachment&.attached?

      path = image.style(:product)&.dig(:url)
      path && base_url && path.start_with?('/') ? "#{base_url}#{path}" : path
    rescue StandardError
      nil
    end

    def variant_url(variant)
      return unless variant

      helpers = Rails.application.routes.url_helpers
      base_url ? helpers.rails_representation_url(variant, host: base_url) : helpers.rails_representation_path(variant, only_path: true)
    end
  end
end
