module Reviews
  # The rows for the Google Product Review Feed (schema v2.4; M8 in
  # docs/plans/2026-11-26-reviews-api-contract.md), rendered by
  # app/views/feeds/google_product_reviews/show.xml.builder.
  #
  # Included: every published retail review of a product the public can see, with text. Store
  # reviews, wholesale reviews and star-only ratings are left out. Products (with their properties
  # and SKUs) load in one batch; reviews stream in batches, so memory stays flat.
  class GoogleFeed
    BATCH_SIZE = 500

    attr_reader :site_url, :store

    def initialize(site_url:, store: Spree::Store.default)
      @site_url = site_url.to_s.strip.chomp('/')
      @store = store
    end

    def publisher_name
      store_name
    end

    # `written` trims spaces only; Google rejects content that is all whitespace, so need a
    # non-space character too.
    def reviews
      Spree::Review.published.retail.written.for_products.
        where("#{Spree::Review.quoted_table_name}.body ~ ?", '\\S').
        where(reviewable_id: Spree::Product.publicly_visible.select(:id))
    end

    def any?
      reviews.exists?
    end

    # Changes whenever an included review (or its product) is added, edited, unpublished or
    # removed, so a cached copy is never served after that.
    def cache_key
      count, reviews_at = reviews.pick(Arel.sql('COUNT(*)'), Arel.sql("MAX(#{Spree::Review.quoted_table_name}.updated_at)"))
      products_at = Spree::Product.where(id: reviews.select(:reviewable_id)).maximum(:updated_at)
      ['feeds/google_product_reviews/v1', site_url, store_name, count, reviews_at&.utc&.iso8601(6),
       products_at&.utc&.iso8601(6)].join('|')
    end

    # Yields each included review with its product, oldest id first.
    def each_review
      products = load_products
      reviews.find_each(batch_size: BATCH_SIZE) do |review|
        product = products[review.reviewable_id]
        next unless product

        yield review, product
      end
    end

    def review_url(review, product)
      "#{product_url(product)}#review-#{review.id}"
    end

    def product_url(product)
      "#{site_url}/#{product.slug}"
    end

    def skus(product)
      product.variants_including_master.map { |variant| variant.sku.to_s.strip }.reject(&:empty?).uniq
    end

    # The product's "brand" property, else the store name.
    def brand(product)
      property = product.product_properties.find { |pp| pp.property&.name.to_s.casecmp?('brand') && pp.value.present? }
      property ? property.value.strip : store_name
    end

    def anonymous?(review)
      review.user_id.nil? && review.display_name == Spree::Review::ANONYMOUS_NAME
    end

    # post_fulfillment for reviews from the review request email, unsolicited otherwise.
    def collection_method(review)
      review.source == 'email' ? 'post_fulfillment' : 'unsolicited'
    end

    def timestamp(review)
      (review.published_at || review.created_at).utc.iso8601
    end

    private

    def store_name
      @store_name ||= store&.name.presence || 'Store'
    end

    def load_products
      Spree::Product.publicly_visible.where(id: reviews.select(:reviewable_id)).
        preload(:variants_including_master, product_properties: :property).index_by(&:id)
    end
  end
end
