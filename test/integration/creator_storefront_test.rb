require 'test_helper'

# Public reads of creator products: the storefront product JSON and the digital summary.
class CreatorStorefrontTest < ActionDispatch::IntegrationTest
  setup do
    digital_store
    @marketplace, @packs = marketplace_taxons
    @creator = creator_user(handle: 'nightshift', name: 'Night Shift')
    @product = creator_product(@creator, taxons: [@packs],
                                         manifest: { 'format' => 1, 'samples' => [{ 'file' => 'kick.wav' }, { 'file' => 'snare.wav' }] })
    @product.update!(review_state: 'submitted')
    Creators::Reviewer.approve!(@product, admin_user)
  end

  def attributes_of(product)
    get "/api/v2/storefront/products/#{product.slug}"
    assert_response :success, response.body
    JSON.parse(response.body)['data']['attributes']
  end

  test 'v2 storefront product JSON includes digital_kind and creator {handle,name}' do
    attrs = attributes_of(@product)
    assert_equal 'pack', attrs['digital_kind']
    assert_equal({ 'handle' => 'nightshift', 'name' => 'Night Shift' }, attrs['creator'])
  end

  test 'v2 storefront digital_kind and creator are null for ordinary products' do
    plain = create(:digital_product, name: 'Plain shirt')
    attrs = attributes_of(plain)
    assert attrs.key?('digital_kind')
    assert attrs.key?('creator')
    assert_nil attrs['digital_kind']
    assert_nil attrs['creator']
  end

  test 'a store-made digital product has a kind and no creator' do
    asset = published_asset(kind: 'preset')
    attrs = attributes_of(asset.variant.product)
    assert_equal 'preset', attrs['digital_kind']
    assert_nil attrs['creator']
  end

  test 'the creator name falls back to the application display name' do
    @creator.profile.update!(name: nil)
    assert_equal({ 'handle' => 'nightshift', 'name' => 'Night Shift' }, attributes_of(@product)['creator'])
  end

  test 'library items name the creator' do
    buyer = create(:user)
    Spree::DigitalOwnership.grant!(user: buyer, variant: @product.master, source: 'grant')
    get '/api/v1/library', headers: auth(buyer)
    assert_equal({ 'handle' => 'nightshift', 'name' => 'Night Shift' }, json['items'].first['product']['creator'])
  end

  test 'a 25-product listing reads digital kinds and creators in a constant number of queries' do
    creators = Array.new(3) { |i| creator_user(handle: "maker#{i}x", name: "Maker #{i}") }
    11.times { |i| approved_creator_product(creators[i % 3], price: 2 + i) }
    13.times { published_asset(kind: 'preset') }
    assert_equal 25, Spree::Product.publicly_visible.count

    tables = /spree_digital_assets|spree_user_profiles|spree_creator_applications/
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql] =~ tables && payload[:name] != 'SCHEMA'
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get '/api/v2/storefront/products', params: { per_page: 25 }
    end
    assert_response :success
    data = JSON.parse(response.body)['data']
    assert_equal 25, data.size
    assert_equal 12, data.count { |p| p['attributes']['creator'] }
    assert_equal 25, data.count { |p| p['attributes']['digital_kind'] }
    assert_operator count, :<=, 4, "#{count} queries on assets, profiles and applications"
  end

  test 'digital_summary returns kind, sample count, byte size for published only' do
    get "/api/v1/products/#{@product.slug}/digital_summary"
    assert_response :success
    assert_equal 'pack', json['kind']
    assert_equal 1, json['version']
    assert_equal 2, json['sample_count']
    assert_equal 2, json['file_count']
    assert_equal DigitalAssetsTestHelper::WAV_BYTES.bytesize * 2, json['byte_size']
    assert_equal %w[kick.wav snare.wav], json['files'].map { |f| f['filename'] }.sort
    refute json['files'].first.key?('url')
    assert_equal({ 'handle' => 'nightshift', 'name' => 'Night Shift' }, json['creator'])
  end

  test 'digital_summary is 404 for drafts, unavailable and ordinary products' do
    draft = creator_product(@creator)
    plain = create(:digital_product)
    [draft.slug, plain.slug, 'nope'].each do |slug|
      get "/api/v1/products/#{slug}/digital_summary"
      assert_response :not_found
    end

    @product.update!(available_on: nil)
    get "/api/v1/products/#{@product.slug}/digital_summary"
    assert_response :not_found
  end

  test 'digital_summary shows the live version while an edit waits for review' do
    draft = Spree::DigitalAsset.create!(variant: @product.master, kind: 'pack', manifest: { 'samples' => [] })
    draft.attach_files!([digital_blob(DigitalAssetsTestHelper::WAV_BYTES, 'new.wav')])
    get "/api/v1/products/#{@product.slug}/digital_summary"
    assert_equal 1, json['version']
    assert_equal 2, json['sample_count']
  end
end
