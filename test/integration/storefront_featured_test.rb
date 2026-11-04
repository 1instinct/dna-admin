require 'test_helper'

# The "featured" contract uses stock Spree: a taxon (e.g. collections/featured), looked up by
# permalink, then products filtered by that taxon and sorted by classification position.
# No app code backs this; the test pins Spree's behavior so an upgrade can't silently change it.
class StorefrontFeaturedTest < ActionDispatch::IntegrationTest
  setup do
    media_store
    taxonomy = Spree::Taxonomy.create!(name: 'Collections')
    @featured = Spree::Taxon.create!(name: 'Featured', parent: taxonomy.root, taxonomy: taxonomy)
    @other_taxon = Spree::Taxon.create!(name: 'Other', parent: taxonomy.root, taxonomy: taxonomy)

    @a = media_product(name: 'Alpha')
    @b = media_product(name: 'Bravo')
    @c = media_product(name: 'Charlie')
    @hidden = media_product(name: 'Hidden', available_on: nil)
    @outside = media_product(name: 'Outside')

    [@c, @hidden, @a, @b].each { |p| p.taxons << @featured }
    @outside.taxons << @other_taxon
  end

  def featured_ids
    get "/api/v2/storefront/products?filter[taxons]=#{@featured.id}&sort_by=default"
    assert_response :success
    media_json['data'].map { |p| p['id'].to_i }
  end

  def classification(product)
    Spree::Classification.find_by!(product: product, taxon: @featured)
  end

  test 'taxon permalink lookup returns the taxon' do
    assert_equal 'collections/featured', @featured.permalink
    get '/api/v2/storefront/taxons/collections/featured'
    assert_response :success
    assert_equal @featured.id.to_s, media_json['data']['id']
    assert_equal 'collections/featured', media_json['data']['attributes']['permalink']
  end

  test 'filtered products come back in classification position order, available only' do
    assert_equal [@c.id, @a.id, @b.id], featured_ids
  end

  test 'a product with null available_on is left out' do
    refute_includes featured_ids, @hidden.id
  end

  test 'products outside the taxon are left out' do
    refute_includes featured_ids, @outside.id
  end

  test 'reordering the classification changes the order' do
    # What the admin taxon drag-sort does (Spree API classifications#update).
    classification(@b).insert_at(1)
    assert_equal [@b.id, @c.id, @a.id], featured_ids

    classification(@c).insert_at(classification(@a).reload.position)
    assert_equal [@b.id, @a.id, @c.id], featured_ids
  end

  test 'publishing the hidden product puts it at its taxon position' do
    @hidden.update!(available_on: 1.hour.ago)
    assert_equal [@c.id, @hidden.id, @a.id, @b.id], featured_ids
  end
end
