require 'test_helper'

# M8: GET /feeds/google/product_reviews.xml, the Google Product Review Feed (schema v2.4).
# Contract: docs/plans/2026-11-26-reviews-api-contract.md, "M8 Google product review feed".
class Feeds::GoogleProductReviewsControllerTest < ActionDispatch::IntegrationTest
  XSD_PATH = Rails.root.join('test/fixtures/files/product_reviews.xsd')
  SITE = 'https://shop.example.com'.freeze

  setup do
    reviews_enable!
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @store = media_store
    @product = media_product(name: 'Rib-Knit Wrap Top')
    @product.master.update!(sku: 'WRAP-1')
    @product.set_property('brand', 'Acme Knits')
  end

  teardown { Rails.cache = @original_cache }

  def fetch_feed
    with_env('SITE_URL' => "#{SITE}/") { get '/feeds/google/product_reviews.xml' }
    Nokogiri::XML(response.body)
  end

  def review_ids(doc)
    doc.xpath('/feed/reviews/review/review_id').map { |node| node.text.to_i }
  end

  def node(doc, review, path)
    doc.at_xpath("/feed/reviews/review[review_id='#{review.id}']/#{path}")
  end

  def assert_valid_feed(doc)
    skip "Google's XSD is missing at #{XSD_PATH}; download it from https://www.google.com/shopping/reviews/schema/product/2.4/product_reviews.xsd" unless File.exist?(XSD_PATH)

    errors = Nokogiri::XML::Schema(File.read(XSD_PATH)).validate(doc)
    assert_empty errors.map(&:message), doc.to_xml
  end

  test 'every published retail product review with text, and nothing else' do
    included = published_review(@product, rating: 4, body: 'Lovely knit', title: 'Love it')
    published_review(@product, body: nil)
    published_review(@product, body: "  \n ")
    published_review(@product, body: 'Trade only', channel: 'wholesale')
    published_review(@product, body: 'Waiting', status: 'pending', published_at: nil)
    published_review(@product, body: 'Hidden by admin', status: 'hidden')
    published_review(@store, body: 'Great shop')
    gone = media_product(name: 'Discontinued')
    published_review(gone, body: 'Was nice')
    gone.update_columns(discontinue_on: 1.day.ago)

    doc = fetch_feed
    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_equal [included.id], review_ids(doc)
    assert_valid_feed(doc)
  end

  test 'fields: reviewer, timestamp, title, content, URLs, rating, product ids and flags' do
    review = published_review(@product, rating: 4, body: ' Lovely <knit> & soft ', title: 'Love it',
                                        published_at: Time.zone.parse('2026-11-20 10:30:00'))
    color = Spree::OptionType.create!(name: 'feed-color', presentation: 'Color')
    rose = color.option_values.create!(name: 'rose', presentation: 'Rose')
    @product.option_types << color
    @product.variants.create!(sku: 'WRAP-ROSE-M', price: 10, option_values: [rose])

    doc = fetch_feed
    assert_equal '2.4', doc.at_xpath('/feed/version').text
    assert_equal @store.name, doc.at_xpath('/feed/publisher/name').text
    assert_equal 'Maya R.', node(doc, review, 'reviewer/name').text
    assert_nil node(doc, review, 'reviewer/name/@is_anonymous')
    assert_equal '2026-11-20T10:30:00Z', node(doc, review, 'review_timestamp').text
    assert_equal 'Love it', node(doc, review, 'title').text
    assert_equal 'Lovely <knit> & soft', node(doc, review, 'content').text
    assert_equal "#{SITE}/#{@product.slug}#review-#{review.id}", node(doc, review, 'review_url').text
    assert_equal 'singleton', node(doc, review, 'review_url/@type').text
    overall = node(doc, review, 'ratings/overall')
    assert_equal %w[4 1 5], [overall.text, overall['min'], overall['max']]
    product = node(doc, review, 'products/product')
    assert_equal %w[WRAP-1 WRAP-ROSE-M], product.xpath('product_ids/skus/sku').map(&:text)
    assert_equal ['Acme Knits'], product.xpath('product_ids/brands/brand').map(&:text)
    assert_equal 'Rib-Knit Wrap Top', product.at_xpath('product_name').text
    assert_equal "#{SITE}/#{@product.slug}", product.at_xpath('product_url').text
    assert_equal 'true', node(doc, review, 'is_verified_purchase').text
    assert_equal 'false', node(doc, review, 'is_incentivized_review').text
    assert_equal 'unsolicited', node(doc, review, 'collection_method').text
    assert_valid_feed(doc)
  end

  test 'flags, collection method, anonymous reviewers, no title, brand falls back to the store name' do
    plain = media_product(name: 'Slip Skirt')
    emailed = published_review(@product, body: 'From the email', source: 'email', incentivized: true)
    anonymous = published_review(plain, body: 'Kept after deletion', display_name: Spree::Review::ANONYMOUS_NAME)
    named_guest = published_review(plain, body: 'Guest named like it', display_name: 'Former customer', user: create(:user))

    doc = fetch_feed
    assert_equal 'post_fulfillment', node(doc, emailed, 'collection_method').text
    assert_equal 'true', node(doc, emailed, 'is_incentivized_review').text
    assert_equal 'true', node(doc, anonymous, 'reviewer/name/@is_anonymous').text
    assert_equal 'Former customer', node(doc, anonymous, 'reviewer/name').text
    assert_nil node(doc, named_guest, 'reviewer/name/@is_anonymous'), 'only an anonymized review (no user) is anonymous'
    assert_nil node(doc, anonymous, 'title')
    assert_equal [@store.name], node(doc, anonymous, 'products/product').xpath('product_ids/brands/brand').map(&:text)
    assert_empty node(doc, anonymous, 'products/product').xpath('product_ids/skus'), 'no SKUs, no <skus>'
    assert_valid_feed(doc)
  end

  test 'an empty feed is still valid' do
    doc = fetch_feed
    assert_response :success
    assert_nil doc.at_xpath('/feed/reviews')
    assert_valid_feed(doc)
  end

  test '404 while reviews are switched off' do
    published_review(@product)
    Spree::ReviewSetting.current.update!(enabled: false)
    fetch_feed
    assert_response :not_found
  end

  test 'cached for an hour, refreshed when a review changes' do
    review = published_review(@product, body: 'First words')
    fetch_feed
    assert_equal 'max-age=3600, public', response.headers['Cache-Control']

    queries = count_queries { fetch_feed }
    assert_operator queries, :<=, 4, 'a cache hit only reads the settings, the store and the cache key'

    review.update!(body: 'Edited words')
    assert_equal 'Edited words', node(fetch_feed, review, 'content').text
    Reviews::Moderation.hide!(review, by: media_admin)
    assert_empty review_ids(fetch_feed)
  end

  test 'no N+1: the query count does not grow with products and reviews' do
    first = media_product(name: 'One')
    published_review(first)
    first.set_property('brand', 'One Co')
    baseline = count_queries { fetch_feed }

    Rails.cache.clear
    3.times do |i|
      product = media_product(name: "More #{i}")
      product.set_property('brand', "Brand #{i}")
      2.times { published_review(product) }
    end
    assert_equal 7, review_ids(fetch_feed).size
    Rails.cache.clear
    assert_equal baseline, count_queries { fetch_feed }
  end

  test 'Google XSD validation actually runs' do
    assert File.exist?(XSD_PATH), "Expected Google's v2.4 XSD at #{XSD_PATH}"
    bad = Nokogiri::XML('<feed><version>2.4</version><publisher><name>x</name></publisher><reviews/></feed>')
    refute_empty Nokogiri::XML::Schema(File.read(XSD_PATH)).validate(bad), 'an empty <reviews> is invalid'
  end

  private

  def count_queries(&block)
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
