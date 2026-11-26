require 'test_helper'

class Spree::ReviewAttributeRequestTest < ActiveSupport::TestCase
  test 'product questions: untagged ones everywhere, tagged ones in their taxon and below' do
    taxonomy = Spree::Taxonomy.create!(name: 'Categories')
    tops = Spree::Taxon.create!(name: 'Tops', parent: taxonomy.root, taxonomy: taxonomy)
    knits = Spree::Taxon.create!(name: 'Knits', parent: tops, taxonomy: taxonomy)
    shoes = Spree::Taxon.create!(name: 'Shoes', parent: taxonomy.root, taxonomy: taxonomy)
    quality = create(:review_attribute, key: 'quality')
    fit = create(:review_attribute, :fit, taxons: [tops])
    create(:review_attribute, key: 'width', taxons: [shoes])
    create(:review_attribute, key: 'packaging', applies_to: 'store')
    create(:review_attribute, key: 'old', active: false)

    knit_top = media_product(name: 'Knit Top')
    knit_top.taxons << knits
    assert_equal %w[quality fit], Spree::ReviewAttribute.for_product(knit_top).map(&:key)
    assert_equal %w[quality], Spree::ReviewAttribute.for_product(media_product(name: 'Plain')).map(&:key)
    assert_equal %w[packaging], Spree::ReviewAttribute.for_store.map(&:key)
    assert quality && fit
  end

  test 'bipolar questions need both end labels' do
    refute Spree::ReviewAttribute.new(key: 'fit', label: 'Fit', kind: 'bipolar').valid?
  end

  test 'review links: only the latest token works, and only while the request is open' do
    order = reviews_order(media_product(name: 'Top'))
    request = Spree::ReviewRequest.create!(order: order, email: order.email, status: 'sent', send_after: Time.current,
                                           expires_at: 1.week.from_now)
    old_token = request.issue_token!
    token = request.issue_token!
    assert_nil Spree::ReviewRequest.find_by_token(old_token)
    assert_equal request, Spree::ReviewRequest.find_by_token(token)
    refute_includes request.reload.attributes.values, token, 'the raw token is not stored'

    request.update!(expires_at: 1.minute.ago)
    assert_nil Spree::ReviewRequest.find_by_token(token)
    request.update!(expires_at: nil, status: 'opted_out')
    assert_nil Spree::ReviewRequest.find_by_token(token)
  end

  test 'settings: one row, with the agreed defaults' do
    settings = Spree::ReviewSetting.current
    assert_equal settings, Spree::ReviewSetting.current
    assert_equal 1, Spree::ReviewSetting.count
    assert_equal [7, 10, 7, 50, 50], settings.values_at(:request_delay_days, :international_request_delay_days,
                                                         :reminder_delay_days, :points_per_review, :points_photo_bonus)
    refute settings.enabled, 'reviews ship switched off'
  end
end
