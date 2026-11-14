require 'test_helper'

# GET /api/v1/library, POST /api/v1/library/:ownership_id/links, POST /api/v1/library/claim.
class Spree::Api::V1::LibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @headers = auth(@user)
    @asset = published_asset(price: 10, manifest: { 'format' => 1 },
                             files: { 'kick.wav' => DigitalAssetsTestHelper::WAV_BYTES, 'snare.wav' => 'snare' })
    @variant = @asset.variant
    @ownership = Spree::DigitalOwnership.grant!(user: @user, variant: @variant, source: 'grant')
  end

  teardown { DigitalAssets.reset_config! }

  def free_variant(claimable: true, price: 0, published: true)
    product = create(:digital_product, price: price)
    product.set_property(DigitalAssets.config.claimable_property, claimable ? 'true' : 'false')
    if published
      published_asset(product: product)
    else
      Spree::DigitalAsset.create!(variant: product.master, kind: 'pack')
    end
    product.master
  end

  test 'index lists owned items with live asset files' do
    get '/api/v1/library', headers: @headers
    assert_response :success

    assert json['updated_at'].present?
    assert_equal 1, json['items'].size
    item = json['items'].first
    assert_equal @ownership.id, item['ownership_id']
    assert_equal @variant.id, item['variant_id']
    product = @variant.product
    assert_equal({ 'id' => product.id, 'slug' => product.slug, 'name' => product.name, 'image_url' => nil, 'creator' => nil },
                 item['product'])
    assert_equal 'pack', item['kind']
    assert_equal 'grant', item['source']
    assert item['granted_at'].present?
    assert_nil item['revoked_at']

    asset = item['asset']
    assert_equal @asset.id, asset['id']
    assert_equal 1, asset['version']
    assert_equal @asset.byte_size, asset['byte_size']
    assert_equal 1, asset['manifest']['format']
    files = asset['files'].sort_by { |f| f['filename'] }
    assert_equal %w[kick.wav snare.wav], files.map { |f| f['filename'] }
    assert_equal %w[byte_size content_type filename id md5 sha256], files.first.keys.sort
    assert_equal Digest::MD5.base64digest('snare'), files.last['md5']
  end

  test 'index serves the newest published version and lists no drafts' do
    draft = Spree::DigitalAsset.create!(variant: @variant, kind: 'pack')
    draft.attach_files!([digital_blob('new', 'new.wav')])
    get '/api/v1/library', headers: @headers
    assert_equal 1, json['items'].first['asset']['version']

    draft.publish!
    get '/api/v1/library', headers: @headers
    assert_equal 2, json['items'].first['asset']['version']
    assert_equal %w[new.wav], json['items'].first['asset']['files'].map { |f| f['filename'] }
  end

  test 'index shows only the signed-in user items' do
    Spree::DigitalOwnership.grant!(user: create(:user), variant: published_asset.variant, source: 'grant')
    get '/api/v1/library', headers: @headers
    assert_equal [@ownership.id], json['items'].map { |i| i['ownership_id'] }
  end

  test 'revoked item listed within 7 days with revoked_at, hidden after' do
    @ownership.revoke!('refunded')
    @ownership.update_columns(revoked_at: 6.days.ago)

    get '/api/v1/library', headers: @headers
    assert_equal [@ownership.id], json['items'].map { |i| i['ownership_id'] }
    assert json['items'].first['revoked_at'].present?

    @ownership.update_columns(revoked_at: 8.days.ago)
    get '/api/v1/library', headers: @headers
    assert_equal [], json['items']
  end

  test 'ETag 304 when unchanged' do
    get '/api/v1/library', headers: @headers
    assert_response :success
    etag = response.headers['ETag']
    assert etag.present?

    get '/api/v1/library', headers: @headers.merge('If-None-Match' => etag)
    assert_response :not_modified
    assert_empty response.body

    travel 1.second do
      Spree::DigitalOwnership.grant!(user: @user, variant: published_asset.variant, source: 'grant')
    end
    get '/api/v1/library', headers: @headers.merge('If-None-Match' => etag)
    assert_response :success
    assert_equal 2, json['items'].size
  end

  test 'ETag changes when a new version is published' do
    get '/api/v1/library', headers: @headers
    etag = response.headers['ETag']

    travel 1.second do
      draft = Spree::DigitalAsset.create!(variant: @variant, kind: 'pack')
      draft.attach_files!([digital_blob('v2', 'v2.wav')])
      draft.publish!
    end
    get '/api/v1/library', headers: @headers.merge('If-None-Match' => etag)
    assert_response :success
  end

  test 'links returns one url per file with expires_at ~10 min' do
    freeze_time do
      post "/api/v1/library/#{@ownership.id}/links", headers: @headers, as: :json
      assert_response :success
      links = json['links']
      file_ids = @asset.file_entries.map { |f| f[:id] }
      assert_equal file_ids.sort, links.map { |l| l['file_id'] }.sort
      links.each do |link|
        assert_match %r{\Ahttp://www.example.com/rails/active_storage/disk/}, link['url']
        assert_equal 10.minutes.from_now.iso8601, Time.iso8601(link['expires_at']).iso8601
      end
    end
  end

  test 'links can be limited to some files' do
    file = @asset.file_entries.first
    post "/api/v1/library/#{@ownership.id}/links", params: { file_ids: [file[:id]] }, headers: @headers, as: :json
    assert_response :success
    assert_equal [file[:id]], json['links'].map { |l| l['file_id'] }
  end

  test 'links 404 for another user ownership and for revoked' do
    other = Spree::DigitalOwnership.grant!(user: create(:user), variant: @variant, source: 'grant')
    post "/api/v1/library/#{other.id}/links", headers: @headers, as: :json
    assert_response :not_found

    @ownership.revoke!('order_canceled')
    post "/api/v1/library/#{@ownership.id}/links", headers: @headers, as: :json
    assert_response :not_found

    post '/api/v1/library/999999/links', headers: @headers, as: :json
    assert_response :not_found
  end

  test 'links rate-limits at 61st call in a minute' do
    60.times do
      post "/api/v1/library/#{@ownership.id}/links", headers: @headers, as: :json
      assert_response :success
    end
    post "/api/v1/library/#{@ownership.id}/links", headers: @headers, as: :json
    assert_response :too_many_requests
    assert json['error'].present?

    post "/api/v1/library/#{@ownership.id}/links", headers: auth(create(:user)), as: :json
    assert_response :not_found, 'another user has their own limit'
  end

  test 'claim grants free source for claimable price-0 variant' do
    variant = free_variant
    post '/api/v1/library/claim', params: { variant_id: variant.id }, headers: @headers, as: :json
    assert_response :created
    assert_equal variant.id, json['variant_id']
    assert_equal 'free', json['source']
    assert json['asset']['files'].any?
    assert Spree::DigitalOwnership.active.exists?(user_id: @user.id, variant_id: variant.id, source: 'free')

    post '/api/v1/library/claim', params: { variant_id: variant.id }, headers: @headers, as: :json
    assert_response :success
    assert_equal 1, Spree::DigitalOwnership.where(user_id: @user.id, variant_id: variant.id).count
  end

  test 'claim 422 otherwise' do
    hidden = free_variant
    hidden.product.update!(available_on: nil)
    [free_variant(claimable: false), free_variant(price: 5), free_variant(published: false), hidden].each do |variant|
      post '/api/v1/library/claim', params: { variant_id: variant.id }, headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert json['error'].present?
    end
    post '/api/v1/library/claim', params: { variant_id: 0 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    post '/api/v1/library/claim', headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal [@ownership.id], Spree::DigitalOwnership.where(user_id: @user.id).pluck(:id)
  end

  test 'all endpoints 401 without bearer' do
    get '/api/v1/library'
    assert_response :unauthorized
    post "/api/v1/library/#{@ownership.id}/links", as: :json
    assert_response :unauthorized
    post '/api/v1/library/claim', params: { variant_id: @variant.id }, as: :json
    assert_response :unauthorized

    @user.generate_spree_api_key!
    get '/api/v1/library', headers: { 'X-Spree-Token' => @user.spree_api_key }
    assert_response :unauthorized
  end
end
