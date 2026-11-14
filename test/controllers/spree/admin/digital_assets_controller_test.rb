require 'test_helper'

# Admin "Digital asset" tab on a product, and the ownership panel on the user page.
class Spree::Admin::DigitalAssetsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ActiveJob::TestHelper

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @product = create(:digital_product, name: 'Drum Pack')
    @base = "/admin/products/#{@product.slug}/digital_assets"
  end

  teardown do
    Warden.test_reset!
    DigitalAssets.reset_config!
  end

  def upload(bytes, name, type)
    file = Tempfile.new(['digital', File.extname(name)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end

  def create_params(manifest: '{"format": 1}', files: nil)
    files ||= [upload(DigitalAssetsTestHelper::WAV_BYTES, 'kick.wav', 'audio/wav'),
               upload('{"a":1}', 'notes.json', 'application/json')]
    { digital_asset: { variant_id: @product.master.id, kind: 'pack', manifest: manifest, files: files } }
  end

  test 'product edit page has the tab' do
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{@product.slug}/edit"
    assert_response :success
    assert_includes response.body, @base
  end

  test 'admin uploads files and publishes version 1' do
    login_as(@admin, scope: :spree_user)
    get @base
    assert_response :success

    assert_difference -> { Spree::DigitalAsset.count }, 1 do
      post @base, params: create_params
    end
    asset = Spree::DigitalAsset.last
    assert_redirected_to "http://www.example.com#{@base}/#{asset.id}/edit"
    assert asset.draft?
    assert_equal @product.master, asset.variant
    assert_equal 'pack', asset.kind
    assert_equal 1, asset.manifest['format']
    assert_equal %w[kick.wav notes.json], asset.file_entries.map { |f| f[:filename] }.sort

    get "#{@base}/#{asset.id}/edit"
    assert_response :success
    assert_includes response.body, 'kick.wav'

    post "#{@base}/#{asset.id}/publish"
    assert_redirected_to "http://www.example.com#{@base}"
    assert asset.reload.published?
    assert_equal 1, asset.version
    assert_equal asset, @product.master.reload.live_digital_asset

    get @base
    assert_response :success
    assert_includes response.body, 'published'
  end

  test 'a draft can be edited and lose a file; a published asset can be retired' do
    login_as(@admin, scope: :spree_user)
    post @base, params: create_params
    asset = Spree::DigitalAsset.last
    notes = asset.files.attachments.detect { |a| a.filename.to_s == 'notes.json' }

    patch "#{@base}/#{asset.id}", params: { digital_asset: { kind: 'kit', manifest: '{"format": 2}',
                                                             files: [upload('x', 'snare.wav', 'audio/wav')] } }
    assert_redirected_to "http://www.example.com#{@base}/#{asset.id}/edit"
    asset.reload
    assert_equal 'kit', asset.kind
    assert_equal 2, asset.manifest['format']
    assert_equal %w[kick.wav notes.json snare.wav], asset.file_entries.map { |f| f[:filename] }.sort

    delete "#{@base}/#{asset.id}/files/#{notes.id}"
    assert_equal %w[kick.wav snare.wav], asset.reload.file_entries.map { |f| f[:filename] }.sort

    post "#{@base}/#{asset.id}/publish"
    patch "#{@base}/#{asset.id}", params: { digital_asset: { kind: 'other' } }
    assert_equal 'kit', asset.reload.kind, 'a published asset is not edited in place'

    post "#{@base}/#{asset.id}/retire"
    assert asset.reload.retired?
    assert_nil @product.master.reload.live_digital_asset
  end

  test 'bad manifest JSON, validator errors and disallowed files are refused' do
    login_as(@admin, scope: :spree_user)
    assert_no_difference -> { Spree::DigitalAsset.count } do
      post @base, params: create_params(manifest: '{not json')
    end
    assert_response :unprocessable_entity
    assert_includes response.body, 'not valid JSON'

    DigitalAssets.config.manifest_validators['pack'] = ->(m) { m['format'] == 1 ? [] : ['format must be 1'] }
    assert_no_difference -> { Spree::DigitalAsset.count } do
      post @base, params: create_params(manifest: '{"format": 3}')
    end
    assert_response :unprocessable_entity
    assert_includes response.body, 'format must be 1'

    assert_no_difference -> { Spree::DigitalAsset.count } do
      post @base, params: create_params(files: [upload('MZ', 'run.exe', 'application/x-msdownload')])
    end
    assert_response :unprocessable_entity
    assert_includes response.body, 'run.exe'
  end

  test 'non-admin 403/redirect' do
    asset = published_asset(product: @product)
    get @base
    refute_includes response.body, "digital_asset_#{asset.id}", 'anonymous gets the login page'

    login_as(create(:user), scope: :spree_user)
    get @base
    refute response.successful?
    assert_no_difference -> { Spree::DigitalAsset.count } do
      post @base, params: create_params
    end
    post "#{@base}/#{asset.id}/retire"
    assert asset.reload.published?
  end

  # --- user page: ownership panel --------------------------------------------------------------

  test 'admin grants and revokes ownership from user page' do
    login_as(@admin, scope: :spree_user)
    user = create(:user)
    variant = published_asset(product: @product).variant
    variant.update!(sku: 'PACK-1')

    get "/admin/users/#{user.id}/edit"
    assert_response :success
    assert_includes response.body, 'admin_user_digital_ownerships'
    assert_includes response.body, 'No digital items'

    post "/admin/users/#{user.id}/digital_ownerships", params: { variant: 'PACK-1' }
    assert_redirected_to "http://www.example.com/admin/users/#{user.id}/edit"
    ownership = Spree::DigitalOwnership.find_by!(user_id: user.id, variant_id: variant.id)
    assert ownership.active?
    assert_equal 'grant', ownership.source

    get "/admin/users/#{user.id}/edit"
    assert_includes response.body, 'Drum Pack'

    post "/admin/users/#{user.id}/digital_ownerships/#{ownership.id}/revoke", params: { reason: 'chargeback' }
    assert_redirected_to "http://www.example.com/admin/users/#{user.id}/edit"
    assert ownership.reload.revoked?
    assert_equal 'chargeback', ownership.revoke_reason

    # By variant id too; an unknown or non-digital variant grants nothing.
    post "/admin/users/#{user.id}/digital_ownerships", params: { variant: variant.id.to_s }
    assert Spree::DigitalOwnership.active.exists?(user_id: user.id, variant_id: variant.id)
    assert_no_difference -> { Spree::DigitalOwnership.count } do
      post "/admin/users/#{user.id}/digital_ownerships", params: { variant: 'NOPE' }
      post "/admin/users/#{user.id}/digital_ownerships", params: { variant: create(:digital_product).master.id.to_s }
    end
  end

  test 'non-admins cannot grant or revoke' do
    user = create(:user)
    variant = published_asset(product: @product).variant
    ownership = Spree::DigitalOwnership.grant!(user: user, variant: variant, source: 'grant')
    login_as(create(:user), scope: :spree_user)

    post "/admin/users/#{user.id}/digital_ownerships/#{ownership.id}/revoke"
    assert ownership.reload.active?
    post "/admin/users/#{create(:user).id}/digital_ownerships", params: { variant: variant.id.to_s }
    assert_equal 1, Spree::DigitalOwnership.count
  end
end
