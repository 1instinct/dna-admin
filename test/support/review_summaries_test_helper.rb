# Helpers for the AI summary (M7) and Google feed (M8) tests: published reviews written straight to
# the table (no order or checkout needed), stats refreshed as publishing would, and ENV overrides.
module ReviewSummariesTestHelper
  def published_review(product, rating: 5, body: 'Lovely fabric', channel: 'retail', refresh: true, **attrs)
    review = Spree::Review.create!({ reviewable: product, rating: rating, body: body, channel: channel, status: 'published',
                                     published_at: Time.current, display_name: 'Maya R.' }.merge(attrs))
    Reviews::RefreshStats.call(product) if refresh
    review
  end

  def published_reviews(product, count, **attrs)
    reviews = Array.new(count) { |i| published_review(product, body: "Review number #{i + 1}", refresh: false, **attrs) }
    Reviews::RefreshStats.call(product)
    reviews
  end

  def retail_stat(product)
    Spree::ReviewStat.for(product, 'retail')
  end

  def store_ai_summary(product, review_count:, generated_at: Time.current, hidden: false, **extra)
    retail_stat(product).update!(
      ai_summary: { 'headline' => 'Soft and true to size', 'summary' => 'Buyers like the fabric.',
                    'pros' => [{ 'label' => 'Soft', 'mentions' => 4 }], 'cons' => [], 'fit_consensus' => 'true_to_size',
                    'model' => 'claude-opus-5-5' }.merge(extra.stringify_keys),
      ai_summary_review_count: review_count, ai_summary_generated_at: generated_at, ai_summary_hidden: hidden
    )
  end

  # Sets ENV keys for the block (nil deletes), then restores them.
  def with_env(values)
    originals = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

ActiveSupport::TestCase.include(ReviewSummariesTestHelper)
