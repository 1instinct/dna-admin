require 'test_helper'

# /api/v1/creator/products: a creator's own digital products, from draft to review.
class Spree::Api::V1::Creator::ProductsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PATH = '/api/v1/creator/products'.freeze

  setup do
    digital_store
    @marketplace, @packs = marketplace_taxons
    @creator = creator_user(handle: 'nightshift', name: 'Night Shift')
    @headers = auth(@creator)
  end

  teardown { DigitalAssets.reset_config! }

  def wav(name = 'kick.wav')
    digital_blob(DigitalAssetsTestHelper::WAV_BYTES, name).signed_id
  end

  def create_product(extra = {})
    params = { name: 'Dusty Drums', description: 'Old breaks.', price: '12.50', kind: 'pack',
               taxon_ids: [@packs.id], files: [wav('kick.wav'), wav('snare.wav')], manifest: { format: 1 } }.merge(extra)
    post PATH, headers: @headers.merge('Content-Type' => 'application/json'), params: params.to_json
    assert_response :created, response.body
    Spree::Product.find(json['id'])
  end

  def patch_product(product, params, headers: @headers)
    patch "#{PATH}/#{product.id}", headers: headers.merge('Content-Type' => 'application/json'), params: params.to_json
  end

  def submit(product)
    post "#{PATH}/#{product.id}/submit", headers: @headers
  end

  def library_for(user)
    get '/api/v1/library', headers: auth(user)
    assert_response :success
    json['items']
  end

  test '401 without bearer, 403 for non-creators and suspended creators' do
    get PATH
    assert_response :unauthorized

    get PATH, headers: auth(create(:user))
    assert_response :forbidden

    Spree::CreatorAccount.find_by(user_id: @creator.id).update!(status: 'suspended')
    get PATH, headers: @headers
    assert_response :forbidden
  end

  test 'create makes unavailable draft product with draft asset' do
    image = digital_blob(ShopMediaTestHelper::PNG_BYTES, 'cover.png', 'image/png').signed_id
    audio = digital_blob(DigitalAssetsTestHelper::WAV_BYTES, 'demo.wav').signed_id
    product = create_product(preview_image_signed_id: image, preview_audio_signed_id: audio)

    assert_nil product.available_on
    assert_equal 'draft', product.review_state
    assert_equal @creator.id, product.creator_id
    assert_equal 12.5, product.price.to_f
    assert_equal [@packs.id], product.taxon_ids
    refute product.available?

    assert_equal 'draft', json['review_state']
    assert_equal 'pack', json['kind']
    assert_equal 12.5, json['price']
    assert_equal 'USD', json['currency']
    assert_equal 'Old breaks.', json['description']
    assert_nil json['live_asset_version']
    assert_equal 0, json['sales_count']
    assert_equal 'draft', json['asset']['status']
    assert_nil json['asset']['version']
    assert_equal %w[kick.wav snare.wav], json['asset']['files'].map { |f| f['filename'] }
    assert_equal 1, json['asset']['manifest']['format']
    assert json['preview']['image_url'].present?
    assert json['preview']['audio_url'].present?
    assert json['created_at'] && json['updated_at']

    get "/api/v2/storefront/products/#{product.slug}"
    assert_response :not_found
  end

  test 'create checks kind, manifest, taxons and file types' do
    DigitalAssets.config.kinds = %w[pack preset]
    DigitalAssets.config.manifest_validators['pack'] = ->(manifest) { manifest['format'] == 1 ? [] : ['format must be 1'] }
    headers = @headers.merge('Content-Type' => 'application/json')
    base = { name: 'X', price: '1', kind: 'pack', files: [wav], manifest: { format: 1 } }

    post PATH, headers: headers, params: base.merge(kind: 'shader').to_json
    assert_response :unprocessable_entity
    assert json['fields']['kind']

    post PATH, headers: headers, params: base.merge(manifest: { format: 2 }).to_json
    assert_response :unprocessable_entity
    assert_includes json['fields']['manifest'], 'format must be 1'

    other = Spree::Taxonomy.create!(name: "Other #{SecureRandom.hex(2)}").root
    post PATH, headers: headers, params: base.merge(taxon_ids: [other.id]).to_json
    assert_response :unprocessable_entity
    assert json['fields']['taxon_ids']

    exe = digital_blob('MZ', 'tool.exe', 'application/x-msdownload').signed_id
    post PATH, headers: headers, params: base.merge(files: [exe]).to_json
    assert_response :unprocessable_entity
    assert json['fields']['files']

    post PATH, headers: headers, params: base.merge(name: '').to_json
    assert_response :unprocessable_entity
    assert json['fields']['name']

    assert_equal 0, Spree::Product.where(creator_id: @creator.id).count
  end

  test 'creator sees only own products (other creator id is 404)' do
    mine = create_product
    other = creator_user
    theirs = Spree::Product.create!(name: 'Theirs', price: 1, shipping_category: mine.shipping_category,
                                    creator_id: other.id, review_state: 'draft')
    plain = create(:digital_product, name: 'Store item')

    get PATH, headers: @headers
    assert_response :success
    assert_equal [mine.id], json['products'].map { |p| p['id'] }

    [theirs, plain].each do |product|
      get "#{PATH}/#{product.id}", headers: @headers
      assert_response :not_found
      patch_product(product, { name: 'Mine now' })
      assert_response :not_found
      post "#{PATH}/#{product.id}/submit", headers: @headers
      assert_response :not_found
      delete "#{PATH}/#{product.id}", headers: @headers
      assert_response :not_found
    end
    assert_equal 'Theirs', theirs.reload.name
  end

  test 'submit moves draft to submitted, only from draft or changes_requested' do
    product = create_product
    submit(product)
    assert_response :success, response.body
    assert_equal 'submitted', json['review_state']
    assert product.reload.submitted_at

    submit(product)
    assert_response :unprocessable_entity

    Creators::Reviewer.request_changes!(product, admin_user, 'Louder kick')
    submit(product)
    assert_response :success
    assert_equal 'submitted', product.reload.review_state
  end

  test 'submit needs files' do
    product = create_product(files: [])
    submit(product)
    assert_response :unprocessable_entity
    assert_equal 'draft', product.reload.review_state
  end

  test 'a product in review cannot be edited' do
    product = create_product
    submit(product)
    patch_product(product, { name: 'Changed' })
    assert_response :unprocessable_entity
    assert_equal 'Dusty Drums', product.reload.name
  end

  test 'update changes details, adds, replaces and removes draft files' do
    product = create_product
    snare = product.master.digital_assets.first.files.attachments.detect { |a| a.filename.to_s == 'snare.wav' }
    patch_product(product, { name: 'Dustier Drums', price: '9', files: [wav('kick.wav'), wav('hat.wav')],
                             remove_file_ids: [snare.id] })
    assert_response :success, response.body
    assert_equal 'Dustier Drums', json['name']
    assert_equal 9.0, json['price']
    assert_equal %w[hat.wav kick.wav], json['asset']['files'].map { |f| f['filename'] }.sort
    assert_equal 1, Spree::DigitalAsset.where(variant_id: product.master.id).count
  end

  test 'delete allowed only in draft' do
    product = create_product
    submit(product)
    delete "#{PATH}/#{product.id}", headers: @headers
    assert_response :unprocessable_entity

    draft = create_product(name: 'Scratch')
    delete "#{PATH}/#{draft.id}", headers: @headers
    assert_response :no_content
    assert draft.reload.deleted?
    get PATH, headers: @headers
    assert_equal [product.id], json['products'].map { |p| p['id'] }
  end

  test 'editing files of approved product creates new draft asset version while live version stays served by library' do
    product = create_product
    submit(product)
    Creators::Reviewer.approve!(product.reload, admin_user)
    buyer = create(:user)
    Spree::DigitalOwnership.grant!(user: buyer, variant: product.master, source: 'grant')
    live = library_for(buyer).first['asset']
    assert_equal 1, live['version']

    patch_product(product, { files: [wav('clap.wav')] })
    assert_response :success, response.body
    assert_equal 'draft', json['review_state']
    assert_equal 'draft', json['asset']['status']
    assert_equal 1, json['live_asset_version']
    assert_equal %w[clap.wav kick.wav snare.wav], json['asset']['files'].map { |f| f['filename'] }.sort
    assert product.reload.available?

    # Removing a file from the new draft leaves the live version's files alone.
    kick = json['asset']['files'].detect { |f| f['filename'] == 'kick.wav' }
    patch_product(product, { remove_file_ids: [kick['id']] })
    assert_response :success, response.body

    served = library_for(buyer).first['asset']
    assert_equal 1, served['version']
    assert_equal %w[kick.wav snare.wav], served['files'].map { |f| f['filename'] }.sort
    post "/api/v1/library/#{library_for(buyer).first['ownership_id']}/links", headers: auth(buyer)
    assert_response :success
    assert_equal 2, json['links'].size

    submit(product)
    assert_response :success
    Creators::Reviewer.approve!(product.reload, admin_user)
    updated = library_for(buyer).first['asset']
    assert_equal 2, updated['version']
    assert_equal %w[clap.wav snare.wav], updated['files'].map { |f| f['filename'] }.sort
  end

  test 'files shared with the live version survive removal from the draft and deleting the draft' do
    product = create_product
    submit(product)
    Creators::Reviewer.approve!(product.reload, admin_user)
    live = product.master.live_digital_asset
    live_blobs = live.files.blobs.to_a

    perform_enqueued_jobs do
      patch_product(product, { files: [wav('clap.wav')] })
      assert_response :success, response.body
      kick = json['asset']['files'].detect { |f| f['filename'] == 'kick.wav' }
      patch_product(product, { remove_file_ids: [kick['id']] })
      assert_response :success, response.body
      Spree::DigitalAsset.find(json['asset']['id']).destroy!
    end

    live_blobs.each do |blob|
      assert ActiveStorage::Blob.exists?(blob.id), "#{blob.filename} blob was purged"
      assert ActiveStorage::Blob.service.exist?(blob.key), "#{blob.filename} file was deleted"
    end
    assert_equal 2, live.reload.files.attachments.count
  end

  test 'keep_file_ids keeps a subset of the live files plus the new uploads in a new draft' do
    product = create_product
    submit(product)
    Creators::Reviewer.approve!(product.reload, admin_user)
    live = product.master.live_digital_asset
    kick = live.files.attachments.detect { |a| a.filename.to_s == 'kick.wav' }

    patch_product(product, { files: [wav('clap.wav')], keep_file_ids: [kick.id] })
    assert_response :success, response.body
    assert_equal 'draft', json['asset']['status']
    assert_equal %w[clap.wav kick.wav], json['asset']['files'].map { |f| f['filename'] }.sort
    assert_equal %w[kick.wav snare.wav], live.reload.files.attachments.map { |a| a.filename.to_s }.sort

    # On the existing draft: keep only the clap, nothing new.
    clap = json['asset']['files'].detect { |f| f['filename'] == 'clap.wav' }
    patch_product(product, { files: [], keep_file_ids: [clap['id']] })
    assert_response :success, response.body
    assert_equal %w[clap.wav], json['asset']['files'].map { |f| f['filename'] }
    assert_equal 2, Spree::DigitalAsset.where(variant_id: product.master.id).count
  end

  test 'keep_file_ids ignores ids of other products and other creators' do
    product = create_product
    draft = product.master.digital_assets.first
    snare = draft.files.attachments.detect { |a| a.filename.to_s == 'snare.wav' }
    foreign = creator_product(creator_user).master.digital_assets.first.files.attachments.first
    plain = published_asset.files.attachments.first

    patch_product(product, { files: [wav('hat.wav')], keep_file_ids: [snare.id, foreign.id, plain.id, 0] })
    assert_response :success, response.body
    assert_equal %w[hat.wav snare.wav], json['asset']['files'].map { |f| f['filename'] }.sort
    assert foreign.reload
    assert plain.reload
  end

  test 'omitting files and keep_file_ids leaves the files unchanged' do
    product = create_product
    before = product.master.digital_assets.first.files.attachments.pluck(:id).sort
    patch_product(product, { name: 'Renamed', manifest: { format: 1, bpm: 90 } })
    assert_response :success, response.body
    assert_equal before, json['asset']['files'].map { |f| f['id'] }.sort
    assert_equal 90, json['asset']['manifest']['bpm']
  end

  test 'kept files are re-checked against the upload rules' do
    product = create_product
    Uploads.config.rules[:audio][:max_bytes] = 1
    patch_product(product, { files: [wav('big.wav')], keep_file_ids: [] })
    assert_response :unprocessable_entity
    assert_match(/big.wav is too large/, json['fields']['files'].first)
    Uploads.reset_config!

    # An empty keep list keeps nothing.
    patch_product(product, { files: [wav('hat.wav')], keep_file_ids: [] })
    assert_response :success, response.body
    assert_equal %w[hat.wav], json['asset']['files'].map { |f| f['filename'] }
  ensure
    Uploads.reset_config!
  end

  test 'editing only details of an approved product keeps it approved' do
    product = create_product
    submit(product)
    Creators::Reviewer.approve!(product.reload, admin_user)
    patch_product(product, { description: 'New words' })
    assert_response :success
    assert_equal 'approved', json['review_state']
    assert_equal 1, Spree::DigitalAsset.where(variant_id: product.master.id).count
  end
end
