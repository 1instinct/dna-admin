require 'test_helper'

# M7: Reviews::AiSummaries, the staleness rule, the summarizer's input and storing a summary.
class Reviews::AiSummariesTest < ActiveSupport::TestCase
  setup do
    @settings = reviews_enable!(ai_summary_enabled: true, ai_summary_min_reviews: 5)
    @product = media_product(name: 'Rib-Knit Wrap Top')
  end

  def stale_ids(**args)
    Reviews::AiSummaries.stale(settings: @settings.reload, **args).map(&:reviewable_id)
  end

  def valid_body(overrides = {})
    { 'headline' => 'Soft, runs a little small', 'summary' => 'Most buyers love the fabric.',
      'pros' => [{ 'label' => 'Soft fabric', 'mentions' => 12 }], 'cons' => [{ 'label' => 'Runs small', 'mentions' => 3 }],
      'fit_consensus' => 'runs_small', 'review_count' => 6, 'model' => 'claude-opus-5-5' }.merge(overrides.stringify_keys)
  end

  test 'needs ai_summary_min_reviews published retail reviews with text' do
    published_reviews(@product, 4)
    published_review(@product, body: nil)
    published_review(@product, body: '   ')
    published_review(@product, channel: 'wholesale')
    published_review(@product, status: 'pending')
    assert_empty stale_ids, 'star-only, blank, wholesale and pending reviews do not count'

    published_review(@product)
    assert_equal [@product.id], stale_ids
  end

  test 'nothing while AI summaries are off' do
    published_reviews(@product, 5)
    @settings.update!(ai_summary_enabled: false)
    assert_empty stale_ids
  end

  test 'fresh summary: not stale until 3 new written reviews' do
    published_reviews(@product, 5)
    store_ai_summary(@product, review_count: 5)
    assert_empty stale_ids

    published_reviews(@product, 2)
    published_review(@product, body: nil)
    assert_empty stale_ids, '2 new written reviews and a star-only rating'

    published_review(@product)
    assert_equal [@product.id], stale_ids
  end

  test 'stale after 30 days' do
    published_reviews(@product, 5)
    store_ai_summary(@product, review_count: 5, generated_at: 29.days.ago)
    assert_empty stale_ids
    retail_stat(@product).update!(ai_summary_generated_at: 31.days.ago)
    assert_equal [@product.id], stale_ids
  end

  test 'Regenerate marks it stale, keeps the summary live, and the next PUT clears it' do
    published_reviews(@product, 5)
    store_ai_summary(@product, review_count: 5)
    assert Reviews::AiSummaries.request_regeneration!(@product)
    assert_equal [@product.id], stale_ids

    stat = retail_stat(@product)
    assert stat.ai_summary.key?('regenerate_requested_at')
    assert_not_nil Reviews::AiSummaries.regeneration_requested_at(stat)
    public_summary = Reviews::Presenter.new.summary(@product, 'retail')[:ai_summary]
    assert_equal 'Soft and true to size', public_summary['headline']
    refute public_summary.key?('regenerate_requested_at'), 'the marker never reaches the storefront'

    Reviews::AiSummaries.store!(@product, valid_body('review_count' => 5))
    refute retail_stat(@product).ai_summary.key?('regenerate_requested_at')
    assert_empty stale_ids
  end

  test 'regeneration without a summary does nothing' do
    refute Reviews::AiSummaries.request_regeneration!(@product)
    assert_nil retail_stat(@product).ai_summary
  end

  test 'hidden summaries are skipped, even when old or regenerate was pressed' do
    published_reviews(@product, 9)
    store_ai_summary(@product, review_count: 5, generated_at: 40.days.ago, hidden: true)
    Reviews::AiSummaries.request_regeneration!(@product)
    assert_empty stale_ids
  end

  test 'order: no summary first, then regenerate requests, then oldest; limit 1..25' do
    old = media_product(name: 'Old')
    older = media_product(name: 'Older')
    regenerated = media_product(name: 'Regenerated')
    [@product, old, older, regenerated].each { |product| published_reviews(product, 5) }
    store_ai_summary(old, review_count: 5, generated_at: 31.days.ago)
    store_ai_summary(older, review_count: 5, generated_at: 45.days.ago)
    store_ai_summary(regenerated, review_count: 5, generated_at: 1.day.ago)
    Reviews::AiSummaries.request_regeneration!(regenerated)

    assert_equal [@product.id, regenerated.id, older.id, old.id], stale_ids
    assert_equal [@product.id], stale_ids(limit: 1)
    assert_equal [@product.id], stale_ids(limit: '0'), 'clamped to at least 1'
    assert_equal 4, stale_ids(limit: '999').size
    assert_equal 4, stale_ids(limit: 'abc').size
    assert_equal 25, Reviews::AiSummaries.clamp_limit(100)
    assert_equal 10, Reviews::AiSummaries.clamp_limit(nil)
  end

  test 'products the public cannot see are skipped' do
    published_reviews(@product, 5)
    @product.update_columns(discontinue_on: 1.day.ago)
    assert_empty stale_ids
  end

  test 'input: retail reviews with text, newest first; histogram counts star-only ratings' do
    create(:review_attribute, :fit)
    older = published_review(@product, rating: 4, body: 'Older', published_at: 2.days.ago, attribute_ratings: { 'fit' => 2 })
    newer = published_review(@product, rating: 2, body: 'Newer', title: 'Hmm', published_at: 1.hour.ago)
    published_review(@product, rating: 5, body: nil)
    published_review(@product, rating: 1, body: 'Trade only', channel: 'wholesale')
    published_review(@product, rating: 1, body: 'Waiting', status: 'pending', published_at: nil)
    @product.update!(description: "<p>Soft <b>rib</b> knit &amp; wrap.</p><p>Machine wash.</p>#{'word ' * 600}")

    input = Reviews::AiSummaries.input_for(@product)
    assert_equal [newer.id, older.id], input[:reviews].map { |review| review[:id] }
    assert_equal({ id: newer.id, rating: 2, title: 'Hmm', body: 'Newer', variant_label: nil, attribute_ratings: {},
                   published_at: newer.published_at.utc.iso8601 }, input[:reviews].first)
    assert_equal({ 'fit' => 2 }, input[:reviews].last[:attribute_ratings])
    assert_equal 3, input[:ratings_count]
    assert_equal 2, input[:reviews_count]
    assert_equal({ '1' => 0, '2' => 1, '3' => 0, '4' => 1, '5' => 1 }, input[:histogram])
    assert_equal ['fit'], input[:attributes].map { |attribute| attribute[:key] }

    description = input[:product][:description]
    assert description.start_with?("Soft rib knit & wrap.\nMachine wash.\nword word"), description
    assert description.end_with?('word…'), description
    assert_operator description.length, :<=, 2000
    assert_equal({ id: @product.id, slug: @product.slug, name: 'Rib-Knit Wrap Top' }, input[:product].except(:description))
  end

  test 'input holds at most INPUT_REVIEWS_MAX (2000) reviews' do
    assert_equal 2000, Reviews::AiSummaries::INPUT_REVIEWS_MAX
    published_reviews(@product, 4)
    assert_equal 3, Reviews::AiSummaries.input_for(@product, max_reviews: 3)[:reviews].size
  end

  test 'store!: writes the retail stat; HTML is stripped' do
    now = Time.zone.parse('2026-11-27 12:00')
    stat = Reviews::AiSummaries.store!(@product, valid_body('headline' => '<b>Soft</b> &amp; comfy', 'model' => 'claude-opus-5-5'), now: now)
    assert_equal 'Soft & comfy', stat.ai_summary['headline']
    assert_equal 'claude-opus-5-5', stat.ai_summary['model']
    assert_equal 6, stat.ai_summary_review_count
    assert_equal now, stat.ai_summary_generated_at
    assert_equal 'retail', stat.scope
    assert_equal({ 'headline' => 'Soft & comfy', 'summary' => 'Most buyers love the fabric.',
                   'pros' => [{ 'label' => 'Soft fabric', 'mentions' => 12 }],
                   'cons' => [{ 'label' => 'Runs small', 'mentions' => 3 }], 'fit_consensus' => 'runs_small',
                   'model' => 'claude-opus-5-5', 'review_count' => 6, 'generated_at' => '2026-11-27T12:00:00Z',
                   'source_scope' => 'retail' }, Reviews::AiSummaries.summary_json(stat))
  end

  test 'store!: strict validation' do
    cases = {
      { 'headline' => 'x' * 81 } => 'headline',
      { 'headline' => '<p> </p>' } => 'headline',
      { 'headline' => 12 } => 'headline',
      { 'summary' => 'x' * 601 } => 'summary',
      { 'summary' => nil } => 'summary',
      { 'pros' => Array.new(6) { { 'label' => 'a', 'mentions' => 1 } } } => 'pros',
      { 'cons' => 'none' } => 'cons',
      { 'pros' => [{ 'label' => 'x' * 41, 'mentions' => 1 }] } => 'pros[0].label',
      { 'pros' => [{ 'label' => 'ok', 'mentions' => 0 }] } => 'pros[0].mentions',
      { 'cons' => [{ 'label' => 'ok', 'mentions' => '2' }] } => 'cons[0].mentions',
      { 'cons' => ['ok'] } => 'cons[0]',
      { 'fit_consensus' => 'small' } => 'fit_consensus',
      { 'review_count' => 0 } => 'review_count',
      { 'review_count' => '6' } => 'review_count',
      { 'model' => 5 } => 'model'
    }
    cases.each do |overrides, field|
      error = assert_raises(Reviews::AiSummaries::Invalid, overrides.inspect) { Reviews::AiSummaries.store!(@product, valid_body(overrides)) }
      assert_includes error.fields.keys, field, overrides.inspect
    end
    assert_nil retail_stat(@product).ai_summary

    stat = Reviews::AiSummaries.store!(@product, valid_body('fit_consensus' => nil, 'pros' => [], 'headline' => 'x' * 80))
    assert_nil stat.ai_summary['fit_consensus']
    assert_equal [], stat.ai_summary['pros']
  end
end
