module Reviews
  # Rebuilds a product's (or the store's) Spree::ReviewStat rows, one per scope, from its
  # published reviews, then copies the retail and all-channel numbers onto spree_products so
  # listings can show and sort by them without a join. A few aggregate queries per call.
  #
  # updated_at moves with the copied columns, so cached storefront product JSON is refreshed.
  module RefreshStats
    module_function

    def call(reviewable, now: Time.current)
      stats = Spree::ReviewStat::SCOPES.index_with { |scope| refresh_scope(reviewable, scope) }
      copy_to_product(reviewable, stats, now) if reviewable.is_a?(Spree::Product)
      stats
    end

    def refresh_scope(reviewable, scope)
      reviews = Spree::Review.published.where(reviewable: reviewable).in_scope(scope)
      histogram = (1..5).to_h { |n| [n.to_s, 0] }.merge(reviews.group(:rating).count.transform_keys(&:to_s))
      ratings_count = histogram.values.sum
      total = histogram.sum { |rating, count| rating.to_i * count }

      stat = Spree::ReviewStat.for(reviewable, scope)
      stat.assign_attributes(
        average: ratings_count.zero? ? 0 : (total.to_d / ratings_count).round(2),
        ratings_count: ratings_count,
        reviews_count: reviews.written.count,
        photos_count: ActiveStorage::Attachment.where(record_type: Spree::Review.name, name: 'photos',
                                                      record_id: reviews.select(:id)).count,
        histogram: histogram,
        attribute_averages: attribute_averages(reviews)
      )
      save_stat(stat)
    end

    # { "fit" => { "average" => 2.4, "count" => 31 }, ... } over reviews that answered each one.
    def attribute_averages(reviews)
      sql = <<~SQL
        SELECT ratings.key, AVG(ratings.value::numeric) AS average, COUNT(*) AS count
        FROM spree_reviews, jsonb_each_text(spree_reviews.attribute_ratings) AS ratings(key, value)
        WHERE spree_reviews.id IN (#{reviews.select(:id).to_sql})
        GROUP BY ratings.key
      SQL
      Spree::Review.connection.select_all(sql).each_with_object({}) do |row, out|
        out[row['key']] = { 'average' => row['average'].to_d.round(2).to_f, 'count' => row['count'].to_i }
      end
    end

    # Two requests refreshing the same new product race on the unique index; the loser reloads.
    def save_stat(stat)
      stat.save!
      stat
    rescue ActiveRecord::RecordNotUnique
      existing = Spree::ReviewStat.for(stat.reviewable, stat.scope)
      existing.update!(stat.attributes.slice('average', 'ratings_count', 'reviews_count', 'photos_count', 'histogram',
                                             'attribute_averages'))
      existing
    end

    def copy_to_product(product, stats, now)
      product.update_columns(
        avg_rating: stats['retail'].average, reviews_count: stats['retail'].ratings_count,
        all_avg_rating: stats['all'].average, all_reviews_count: stats['all'].ratings_count,
        updated_at: now
      )
    end
  end
end
