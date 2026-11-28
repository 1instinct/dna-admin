require 'test_helper'

# config/initializers/spree_admin_native_resources.rb: the admin types the Spree Admin Native app
# shows under More, read and changed through /api/admin_native/v1/resources with an admin API key.
class SpreeAdminNativeResourcesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BASE = '/api/admin_native/v1/resources'.freeze
  EXPO_URL = 'https://exp.host/--/api/v2/push/send'.freeze
  # The gem's own pattern plus the credentials this app keeps under other names.
  SECRET_LOOKING = /password|token|secret|digest|encrypted|api_key|salt|otp|private_key|credentials|stream_key|signed_payload|jwt|cvv/i.freeze
  SECRET_VALUES = %w[ExponentPushToken[device-secret] sk-live-stream-secret signed.jws.payload acct-token-secret].freeze

  # Type => model. A fork without one of these models (a feature it doesn't carry) has no such type.
  MODELS = {
    'menu_locations' => 'MenuLocation', 'menu_items' => 'MenuItem', 'homepage_sections' => 'HomepageSection',
    'app_settings' => 'AppSetting', 'admin_theme' => 'AdminTheme', 'pages' => 'Spree::Page',
    'push_notifications' => 'PushNotification', 'push_subscriptions' => 'PushSubscription', 'live_streams' => 'LiveStream',
    'contacts' => 'Contact', 'messages' => 'Message', 'threads' => 'ThreadTable',
    'creator_applications' => 'Spree::CreatorApplication', 'creator_accounts' => 'Spree::CreatorAccount',
    'creator_reviews' => 'Spree::Product', 'creator_earnings' => 'Spree::CreatorEarning',
    'creator_payouts' => 'Spree::CreatorPayout', 'content_reports' => 'Spree::ContentReport',
    'account_locks' => 'Spree::User', 'user_profiles' => 'Spree::UserProfile', 'app_feedback' => 'AppFeedback',
    'affiliate_accounts' => 'AffiliateAccount', 'affiliate_commissions' => 'AffiliateCommission',
    'affiliate_payouts' => 'AffiliatePayout', 'digital_assets' => 'Spree::DigitalAsset',
    'digital_ownerships' => 'Spree::DigitalOwnership', 'content_assets' => 'ContentAsset',
    'entitlements' => 'Spree::Entitlement', 'iap_products' => 'Spree::IapProduct', 'iap_transactions' => 'Spree::IapTransaction',
    'product_videos' => 'Spree::ProductVideo'
  }.freeze
  TYPES = MODELS.keys.select { |key| MODELS[key].safe_constantize }.freeze

  setup do
    @admin = admin_user
    @admin.generate_spree_api_key!
  end

  # values is positional so a literal hash isn't taken for keywords on Ruby 2.7.
  def call(method, path, values = nil, api_key = @admin.spree_api_key, extra = {})
    headers = { 'X-Spree-Token' => api_key, 'CONTENT_TYPE' => 'application/json' }
    body = values ? { values: values }.merge(extra) : (extra.any? ? extra : nil)
    send(method, "#{BASE}#{path}", params: body&.to_json, headers: headers)
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def run_action(key, record, action, input = nil)
    call(:post, "/#{key}/#{record.id}/actions/#{action}", nil, @admin.spree_api_key, input ? { input: input } : {})
  end

  # POST resources/uploads, as the app does before it sends an image or file field.
  def upload(name = 'test-image.png', content_type = 'image/png')
    file = name.is_a?(String) ? fixture_file_upload(name, content_type) : name
    post "#{BASE}/uploads", params: { file: file }, headers: { 'X-Spree-Token' => @admin.spree_api_key }
    assert_equal 201, response.status, response.body
    JSON.parse(response.body)['data']
  end

  def manifest_of(key)
    call(:get, '')['data'].find { |type| type['key'] == key }
  end

  def ids_of(body)
    body['data'].map { |record| record['id'].to_i }
  end

  def actions_of(key, record)
    call(:get, "/#{key}/#{record.id}").dig('data', 'actions')
  end

  def stub_expo(status: 200)
    stub_request(:post, EXPO_URL).to_return(status: status, body: '{"data":[]}', headers: { 'Content-Type' => 'application/json' })
  end

  # One record of each type.
  def sample(key)
    case key
    when 'menu_locations' then MenuLocation.create!(title: 'Main menu', location: 'header', is_visible: true)
    when 'menu_items' then MenuItem.create!(name: 'Shop', url: '/shop', menu_location: sample('menu_locations'))
    when 'homepage_sections' then HomepageSection.create!(title: 'Hero', section_type: 'hero', position: 1)
    when 'app_settings' then AppSetting.create!(platform: 'android', version: '1.2.3')
    when 'admin_theme' then AdminTheme.first_or_create!
    when 'pages' then Spree::Page.create!(title: 'About', slug: '/about-us', body: 'Who we are')
    when 'push_notifications' then PushNotification.create!(title: 'Hello', body: 'Something new')
    when 'push_subscriptions'
      PushSubscription.create!(user: create(:user), token: 'ExponentPushToken[device-secret]', platform: 'ios', device_name: 'Test phone')
    when 'live_streams'
      LiveStream.create!(title: 'Launch', actor: create(:user), stream_key: 'sk-live-stream-secret', stream_id: 'stream-1', status: 'idle')
    when 'contacts' then Contact.create!(full_name: 'Ada Example', email: 'ada@example.com', actor: create(:user))
    when 'messages' then Message.create!(sender: sample('contacts'), receiver: create(:user), message: 'Hi there')
    when 'threads' then ThreadTable.create!(archived: false, stale: false)
    when 'creator_applications' then create(:creator_application)
    when 'creator_accounts' then Spree::CreatorAccount.find_by!(user_id: creator_user.id)
    when 'creator_reviews' then submitted_creator_product
    when 'creator_earnings' then create(:creator_earning)
    when 'creator_payouts'
      Spree::CreatorPayout.create!(creator_account: create(:creator_account), amount: 5, currency: 'USD', reference: 'PAY-1',
                                   paid_at: Time.current)
    when 'content_reports' then create(:content_report)
    when 'account_locks' then create(:user)
    when 'user_profiles' then create(:user_profile)
    when 'app_feedback' then create(:app_feedback)
    when 'affiliate_accounts' then create(:affiliate_account)
    when 'affiliate_commissions' then create(:affiliate_commission)
    when 'affiliate_payouts' then create(:affiliate_payout)
    when 'digital_assets' then create(:digital_asset)
    when 'digital_ownerships' then create(:digital_ownership)
    when 'content_assets' then create(:content_asset)
    when 'entitlements' then Spree::Entitlement.create!(user: create(:user), key: 'pro', active: true)
    when 'iap_products' then create(:iap_product)
    when 'iap_transactions' then create(:iap_transaction, signed_payload: 'signed.jws.payload', account_token: 'acct-token-secret')
    when 'product_videos' then media_video(media_product)
    end
  end

  def submitted_creator_product
    product = creator_product(creator_user)
    product.update!(review_state: 'submitted', submitted_at: Time.current)
    product
  end

  def refute_secrets(body, context)
    text = body.is_a?(String) ? body : body.to_json
    SECRET_VALUES.each { |value| refute_includes text, value, "#{context} shows a secret" }
    refute_includes text, @admin.spree_api_key, "#{context} shows the API key"
  end

  # --- Every type ------------------------------------------------------------------------------

  test 'every type is registered, needs an admin, and is announced' do
    available = SpreeAdminNative.resources.available.map(&:key)
    MODELS.each do |key, model|
      assert_equal !model.safe_constantize.nil?, available.include?(key), "#{key} is available exactly when #{model} exists"
    end

    get '/api/admin_native/v1/capabilities', headers: { 'X-Spree-Token' => @admin.spree_api_key }
    assert_includes JSON.parse(response.body)['capabilities'], 'admin.resources'

    call(:get, '', nil, nil)
    assert_equal 401, response.status
    customer = create(:user)
    customer.generate_spree_api_key!
    call(:get, '/menu_items', nil, customer.spree_api_key)
    assert_equal 401, response.status
  end

  test 'the manifest describes every available type without secret-looking fields' do
    data = call(:get, '')['data']
    assert_equal 200, response.status
    assert_equal SpreeAdminNative.resources.available.map(&:key).sort, data.map { |d| d['key'] }.sort
    data.each do |type|
      names = type['fields'].map { |f| f['name'] }
      assert names.any?, "#{type['key']} has no fields"
      names.each { |name| refute_match SECRET_LOOKING, name, "#{type['key']} exposes #{name}" }
      model = SpreeAdminNative.resources[type['key']].model_class
      title = type['title_field']
      assert model.column_names.include?(title) || model.method_defined?(title), "#{type['key']} title #{title}"
      (type['list_fields'] - ['id']).each { |name| assert_includes names, name, "#{type['key']} lists #{name}" }
      type['fields'].select { |f| f['type'] == 'reference' }.each do |field|
        assert SpreeAdminNative.resources[field['resource']], "#{type['key']}.#{field['name']} points at #{field['resource']}"
      end
    end
    groups = data.map { |d| d['group'] }.uniq
    assert_includes groups, 'Storefront'
    assert_includes groups, 'Engagement'
    assert_includes groups, 'Community and creators'
    assert_includes groups, 'Commerce extras'
  end

  test 'every type lists, searches and shows a record without secrets' do
    TYPES.each do |key|
      record = sample(key)
      assert record&.persisted?, "no sample for #{key}"

      body = call(:get, "/#{key}?per_page=100")
      assert_equal 200, response.status, "#{key} list: #{response.body}"
      assert_operator body.dig('meta', 'total_count'), :>=, 1, key
      refute_secrets(response.body, "#{key} list")

      if SpreeAdminNative.resources[key].search_attrs.any?
        call(:get, "/#{key}?q=zz-nothing-matches-zz")
        assert_equal 200, response.status, "#{key} search: #{response.body}"
      end

      body = call(:get, "/#{key}/#{record.id}")
      assert_equal 200, response.status, "#{key} show: #{response.body}"
      assert_equal record.id.to_s, body.dig('data', 'id')
      body.dig('data', 'values').each_key { |name| refute_match SECRET_LOOKING, name, "#{key} value #{name}" }
      refute_secrets(response.body, "#{key} show")
    end
  end

  test 'forks change a type with configure, in any load order' do
    registry = SpreeAdminNative.resources
    seen = []
    # Registered before the type, as a fork's initializer (loaded first) does, and after it.
    registry.configure('scratch_menu_items') { |r| seen << :before; r.field :item_class, :string, label: 'Badge' }
    registry.register('scratch_menu_items') do |r|
      r.model 'MenuItem'
      r.label 'Scratch'
      r.fields :auto
    end
    registry.configure('scratch_menu_items') { |r| seen << :after; r.search :name, :item_class }
    assert_equal %i[before after], seen
    definition = registry['scratch_menu_items']
    assert_equal 'Badge', definition.resolved_field(:item_class).label
    assert_equal %i[name item_class], definition.search_attrs

    # Each type here takes configure blocks: they run now, and again whenever it is registered.
    keys = []
    registry.configure('push_notifications') { |r| keys << r.key }
    assert_equal ['push_notifications'], keys
  ensure
    registry.unregister('scratch_menu_items')
    configurations = registry.instance_variable_get(:@configurations)
    configurations.delete('scratch_menu_items')
    configurations['push_notifications']&.pop
  end

  test 'the 0.4 load hook still runs after each type is registered' do
    seen = {}
    # Runs at once for the types registered at boot, and again after every reload.
    ActiveSupport.on_load(:spree_admin_native_resource, yield: true) { |r| seen[r.key] = r.label }
    MODELS.each_key { |key| assert seen.key?(key), "no hook for #{key}" }
    assert_equal 'Push notifications', seen['push_notifications']
  end

  test 'every available type lists, with or without records' do
    SpreeAdminNative.resources.available.each do |definition|
      call(:get, "/#{definition.key}")
      assert_equal 200, response.status, "#{definition.key}: #{response.body}"
    end
  end

  test 'filters take the declared options' do
    sample('push_notifications')
    body = call(:get, '/push_notifications?filter[status]=draft')
    assert_equal 200, response.status
    assert body['data'].all? { |n| n.dig('values', 'status') == 'draft' }
    call(:get, '/homepage_sections?filter[is_visible]=true')
    assert_equal 200, response.status
  end

  # --- Writes follow the Rails admin ---------------------------------------------------------------

  test 'read-only types refuse writes' do
    (%w[push_subscriptions creator_applications creator_earnings creator_payouts content_reports account_locks
        user_profiles affiliate_commissions affiliate_payouts digital_assets digital_ownerships entitlements
        iap_transactions] & TYPES).each do |key|
      record = sample(key)
      call(:post, "/#{key}", { 'id' => 1 })
      assert_equal 403, response.status, "#{key} create"
      call(:patch, "/#{key}/#{record.id}", { 'id' => 1 })
      assert_equal 403, response.status, "#{key} update"
      call(:delete, "/#{key}/#{record.id}")
      assert_equal 403, response.status, "#{key} delete"
    end
    %w[live_streams creator_accounts creator_reviews app_feedback affiliate_accounts admin_theme].each do |key|
      call(:post, "/#{key}", {})
      assert_equal 403, response.status, "#{key} create"
    end
  end

  test 'menu locations and items are written as in the admin' do
    location = call(:post, '/menu_locations', { title: 'Footer', location: 'footer', is_visible: true })
    assert_equal 201, response.status, response.body
    item = call(:post, '/menu_items', { name: 'About', link: { kind: 'url', url: '/about' }, menu_location_id: location.dig('data', 'id') })
    assert_equal 201, response.status, response.body
    assert_equal({ 'kind' => 'url', 'url' => '/about' }, item.dig('data', 'values', 'link').slice('kind', 'url'))
    assert_equal ['/about', 'url', nil], MenuItem.find(item.dig('data', 'id')).values_at(:url, :item_class, :item_id)
    assert_equal({ 'id' => location.dig('data', 'id'), 'title' => 'Footer' }, item.dig('data', 'values', 'menu_location_id'))

    child = call(:post, '/menu_items', { name: 'Team', menu_location_id: location.dig('data', 'id'), parent_id: item.dig('data', 'id') })
    assert_equal 201, response.status, response.body
    call(:patch, "/menu_items/#{item.dig('data', 'id')}", { is_visible: false })
    assert_nil MenuItem.find(item.dig('data', 'id')).is_visible, 'is_visible is not in the admin permitted params'

    shown = call(:get, "/menu_items/#{item.dig('data', 'id')}")
    assert_equal({ 'update' => true, 'destroy' => false }, shown.dig('data', 'can'), 'an item with children is kept')
    call(:delete, "/menu_items/#{item.dig('data', 'id')}")
    assert_equal 403, response.status
    assert MenuItem.exists?(item.dig('data', 'id'))
    refute MenuItem.find(item.dig('data', 'id')).destroy, 'MenuItem still refuses it'
    call(:delete, "/menu_items/#{child.dig('data', 'id')}")
    assert_equal 204, response.status
    call(:delete, "/menu_items/#{item.dig('data', 'id')}")
    assert_equal 204, response.status

    parent = MenuItem.create!(name: 'Parent', menu_location_id: location.dig('data', 'id').to_i)
    MenuItem.create!(name: 'Child', menu_location_id: location.dig('data', 'id').to_i, parent_id: parent.id)
    call(:delete, "/menu_locations/#{location.dig('data', 'id')}")
    assert_equal 204, response.status, 'a location still deletes its items'
    refute MenuItem.where(menu_location_id: location.dig('data', 'id').to_i).exists?
  end

  test 'homepage sections validate their settings' do
    if HomepageSection.const_defined?(:URL_SETTINGS_FIELDS)
      call(:post, '/homepage_sections', { title: 'Get the app', section_type: 'app_links', settings: { ios_url: 'apps.example.com' } })
      assert_equal 422, response.status, 'links must be absolute'
    end
    call(:post, '/homepage_sections', { title: 'Get the app', section_type: 'no_such_type' })
    assert_equal 422, response.status
    body = call(:post, '/homepage_sections', { title: 'Get the app', section_type: 'app_links',
                                               settings: { ios_url: 'https://apps.example.com/app' } })
    assert_equal 201, response.status, response.body
    assert_equal 'https://apps.example.com/app', body.dig('data', 'values', 'settings', 'ios_url')
  end

  test 'app versions are added and deleted, not edited' do
    body = call(:post, '/app_settings', { platform: 'android', version: '2.0.0', build: '7' })
    assert_equal 201, response.status, response.body
    call(:patch, "/app_settings/#{body.dig('data', 'id')}", { version: '3.0.0' })
    assert_equal 403, response.status
    call(:delete, "/app_settings/#{body.dig('data', 'id')}")
    assert_equal 204, response.status
  end

  test 'the theme is edited in place and shows at once' do
    theme = sample('admin_theme')
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(AdminTheme::CACHE_KEY, 'stale theme')
    call(:patch, "/admin_theme/#{theme.id}", { brand_name: 'Studio', primary_color: 'red' })
    assert_equal 422, response.status
    call(:patch, "/admin_theme/#{theme.id}", { brand_name: 'Studio', color_mode: 'dark' })
    assert_equal 200, response.status, response.body
    assert_equal %w[Studio dark], [theme.reload.brand_name, theme.color_mode]
    assert_nil Rails.cache.read(AdminTheme::CACHE_KEY), 'the cached theme is dropped'
    call(:delete, "/admin_theme/#{theme.id}")
    assert_equal 403, response.status
  ensure
    Rails.cache = original_cache if original_cache
  end

  test 'app feedback is triaged, not rewritten' do
    feedback = sample('app_feedback')
    call(:patch, "/app_feedback/#{feedback.id}", { status: 'triaged', admin_note: 'Seen', message: 'changed', kind: 'idea' })
    assert_equal 200, response.status, response.body
    feedback.reload
    assert_equal %w[triaged Seen], [feedback.status, feedback.admin_note]
    assert_equal %w[bug], [feedback.kind]
    refute_equal 'changed', feedback.message
  end

  test 'creator accounts change only their terms' do
    account = sample('creator_accounts')
    call(:patch, "/creator_accounts/#{account.id}", { revenue_share_bps: 6000, status: 'suspended', user_id: 1 })
    assert_equal 200, response.status, response.body
    account.reload
    assert_equal [6000, 'active'], [account.revenue_share_bps, account.status]
  end

  test 'live streams edit their details only' do
    stream = sample('live_streams')
    call(:patch, "/live_streams/#{stream.id}", { title: 'Renamed', status: 'active', stream_url: 'rtmps://elsewhere' })
    assert_equal 200, response.status, response.body
    stream.reload
    assert_equal ['Renamed', 'idle', nil], [stream.title, stream.status, stream.stream_url]
    call(:delete, "/live_streams/#{stream.id}")
    assert_equal 403, response.status
  end

  # --- Push notifications ----------------------------------------------------------------------

  test 'a draft is sent once with Send now, then kept as it was sent' do
    PushSubscription.create!(user: create(:user), token: 'ExponentPushToken[a]', platform: 'ios')
    PushSubscription.create!(user: create(:user), token: 'ExponentPushToken[b]', platform: 'android')
    stub_expo
    body = call(:post, '/push_notifications', { title: 'Sale', body: 'Today only', notification_type: 'promo',
                                                target: 'all', data: { promoCode: 'SAVE10' }, status: 'sent', sent_count: 99 })
    assert_equal 201, response.status, response.body
    id = body.dig('data', 'id')
    assert_equal ['draft', 0], [body.dig('data', 'values', 'status'), body.dig('data', 'values', 'sent_count')]
    assert_equal ['deliver'], body.dig('data', 'actions')

    call(:patch, "/push_notifications/#{id}", { title: 'Big sale' })
    assert_equal 200, response.status

    body = call(:post, "/push_notifications/#{id}/actions/deliver")
    assert_equal 200, response.status, response.body
    assert_equal 'Sent to 2 device(s).', body['message']
    notification = PushNotification.find(id)
    assert_equal ['sent', 2, 0, @admin.id], [notification.status, notification.sent_count, notification.error_count, notification.sent_by_id]
    assert_equal({ 'promoCode' => 'SAVE10', 'type' => 'promo' }, notification.data)
    assert_requested(:post, EXPO_URL, times: 1) { |req| JSON.parse(req.body).first['title'] == 'Big sale' }
    assert_equal [], body.dig('data', 'actions')

    call(:post, "/push_notifications/#{id}/actions/deliver")
    assert_equal 422, response.status, 'sent only once'
    assert_equal({ 'update' => false, 'destroy' => false }, body.dig('data', 'can'))
    call(:patch, "/push_notifications/#{id}", { title: 'Rewritten' })
    assert_equal 403, response.status
    call(:delete, "/push_notifications/#{id}")
    assert_equal 403, response.status
    assert_equal 'Big sale', notification.reload.title
    assert_requested(:post, EXPO_URL, times: 1)
    # The model still refuses it, for every other client.
    refute notification.update(title: 'Rewritten')
    refute notification.destroy
  end

  test 'a draft records the admin who made it, and is editable and deletable while a draft' do
    body = call(:post, '/push_notifications', { title: 'Draft', body: 'Not yet', sent_by_id: create(:user).id })
    assert_equal 201, response.status, response.body
    assert_equal({ 'id' => @admin.id.to_s, 'title' => @admin.email }, body.dig('data', 'values', 'sent_by_id'))
    assert_equal({ 'update' => true, 'destroy' => true }, body.dig('data', 'can'))
    assert_equal @admin.id, PushNotification.find(body.dig('data', 'id')).sent_by_id
    call(:patch, "/push_notifications/#{body.dig('data', 'id')}", { title: 'Still a draft' })
    assert_equal 200, response.status
    assert_equal @admin.id, PushNotification.find(body.dig('data', 'id')).sent_by_id, 'only set on create'
  end

  test 'Send now to one user, failures recorded, drafts deleted' do
    user = create(:user)
    PushSubscription.create!(user: user, token: 'ExponentPushToken[u]', platform: 'ios')
    stub_expo(status: 500)
    draft = PushNotification.create!(title: 'Order', body: 'Shipped', target: 'user')
    run_action('push_notifications', draft, 'deliver')
    assert_equal 422, response.status, 'a user target needs the user'
    assert_equal 'draft', draft.reload.status

    draft.update!(target_user_id: user.id)
    body = run_action('push_notifications', draft, 'deliver')
    assert_equal 200, response.status, response.body
    assert_equal ['failed', 0, 1], [draft.reload.status, draft.sent_count, draft.error_count]
    assert_includes body['message'], '1 error'

    other = PushNotification.create!(title: 'Oops', body: 'Draft')
    call(:delete, "/push_notifications/#{other.id}")
    assert_equal 204, response.status
  end

  # --- Community and creators ------------------------------------------------------------------

  test 'creator applications are approved or rejected once' do
    application = sample('creator_applications')
    assert_equal %w[approve reject], actions_of('creator_applications', application)
    run_action('creator_applications', application, 'approve')
    assert_equal 200, response.status, response.body
    assert application.reload.approved?
    assert_equal @admin.id, application.reviewed_by_id
    assert Creators.creator?(application.user.reload)
    assert Spree::CreatorAccount.find_by(user_id: application.user_id).active?
    run_action('creator_applications', application, 'reject')
    assert_equal 422, response.status

    other = sample('creator_applications')
    run_action('creator_applications', other, 'reject')
    assert_equal 200, response.status
    assert other.reload.rejected?
    refute Creators.creator?(other.user.reload)
  end

  test 'creators are suspended, reinstated and revoked as in the admin' do
    account = sample('creator_accounts')
    assert_equal %w[suspend revoke], actions_of('creator_accounts', account)
    run_action('creator_accounts', account, 'suspend')
    assert_equal 200, response.status
    assert account.reload.suspended?
    run_action('creator_accounts', account, 'suspend')
    assert_equal 422, response.status
    run_action('creator_accounts', account, 'reinstate')
    assert_equal 200, response.status
    assert account.reload.active?

    run_action('creator_accounts', account, 'revoke')
    assert_equal 200, response.status
    assert account.reload.suspended?
    refute Creators.creator?(account.user.reload)
    body = run_action('creator_accounts', account, 'reinstate')
    assert_equal 422, response.status
    assert_includes body.dig('error', 'message'), 'no longer has the creator role'
    assert account.reload.suspended?
  end

  test 'creator products are reviewed from the queue with a note' do
    marketplace_taxons
    product = sample('creator_reviews')
    assert_equal %w[approve request_changes reject], actions_of('creator_reviews', product)
    inputs = manifest_of('creator_reviews')['actions'].map { |a| [a['name'], a['inputs'].map { |i| [i['name'], i['required']] }] }.to_h
    assert_equal({ 'approve' => [['note', false]], 'request_changes' => [['note', true]], 'reject' => [['note', true]] }, inputs)

    %w[reject request_changes].each do |action|
      body = run_action('creator_reviews', product, action, { note: '  ' })
      assert_equal 422, response.status, "#{action} needs a note"
      assert_equal ["can't be blank"], body.dig('error', 'fields', 'note')
    end
    assert_equal 'submitted', product.reload.review_state

    call(:patch, "/creator_reviews/#{product.id}", { review_note: 'Draft note', name: 'Renamed', review_state: 'approved' })
    assert_equal 200, response.status, response.body
    assert_equal ['submitted', 'Draft note'], [product.reload.review_state, product.review_note]
    refute_equal 'Renamed', product.name
    body = run_action('creator_reviews', product, 'request_changes', { note: 'Trim the intro' })
    assert_equal 200, response.status, response.body
    assert body['removed'], 'a decided product leaves the queue'
    assert_equal ['changes_requested', 'Trim the intro'], [product.reload.review_state, product.review_note]
    call(:get, "/creator_reviews/#{product.id}")
    assert_equal 404, response.status
    run_action('creator_reviews', product, 'reject', { note: 'Too late' })
    assert_equal 404, response.status, 'no longer reviewable'

    rejected = sample('creator_reviews')
    run_action('creator_reviews', rejected, 'reject', { note: 'Not original' })
    assert_equal 200, response.status, response.body
    assert_equal ['rejected', 'Not original'], [rejected.reload.review_state, rejected.review_note]

    approved = sample('creator_reviews')
    approved.update!(review_note: 'Saved earlier')
    body = run_action('creator_reviews', approved, 'approve', { note: 'Lovely' })
    assert_equal 200, response.status, response.body
    assert_equal 'Lovely', approved.reload.review_note
    assert_equal 'approved', approved.review_state
    assert approved.available_on.present?
    assert approved.master.digital_assets.published.exists?

    store_product = media_product
    call(:get, "/creator_reviews/#{store_product.id}")
    assert_equal 404, response.status, 'store products are not in the queue'
  end

  test 'creator earnings are voided only while unpaid' do
    earning = sample('creator_earnings')
    paid = create(:creator_earning, state: 'paid')
    assert_equal %w[void], actions_of('creator_earnings', earning)
    assert_equal [], actions_of('creator_earnings', paid)
    run_action('creator_earnings', earning, 'void')
    assert_equal 200, response.status
    assert_equal %w[void admin], [earning.reload.state, earning.void_reason]
    run_action('creator_earnings', paid, 'void')
    assert_equal 422, response.status
    assert paid.reload.paid?
  end

  test 'creator earnings past their hold read as payable' do
    earning = create(:creator_earning, payable_at: 1.minute.ago)
    body = call(:get, "/creator_earnings/#{earning.id}")
    assert_equal 'payable', body.dig('data', 'values', 'state')
  end

  test 'reports are dismissed or acted on through Profiles::Moderation' do
    report = sample('content_reports')
    assert_equal %w[dismiss hide_profile remove_photo clear_bio lock_account], actions_of('content_reports', report)
    run_action('content_reports', report, 'hide_profile')
    assert_equal 200, response.status, response.body
    report.reload
    assert_equal ['actioned', @admin.id, 'Profile hidden'], [report.status, report.resolved_by_id, report.resolution_note]
    assert report.reportable.reload.hidden?
    assert_equal [], actions_of('content_reports', report)
    run_action('content_reports', report, 'dismiss')
    assert_equal 422, response.status

    dismissed = sample('content_reports')
    run_action('content_reports', dismissed, 'dismiss')
    assert_equal 200, response.status
    assert_equal ['dismissed', nil], [dismissed.reload.status, dismissed.resolution_note]

    cleared = sample('content_reports')
    cleared.reportable.update!(bio: 'Buy followers')
    run_action('content_reports', cleared, 'clear_bio')
    assert_equal 200, response.status
    assert_nil cleared.reportable.reload.bio

    locked = sample('content_reports')
    run_action('content_reports', locked, 'lock_account')
    assert_equal 200, response.status
    assert locked.reportable.user.reload.locked_at.present?

    admin_profile = create(:user_profile, user: admin_user)
    refused = create(:content_report, reportable: admin_profile)
    body = run_action('content_reports', refused, 'lock_account')
    assert_equal 422, response.status
    assert_includes body.dig('error', 'message'), "can't be locked"
    assert_equal 'open', refused.reload.status
  end

  test 'accounts are locked and unlocked; admins are not locked' do
    user = sample('account_locks')
    user.generate_spree_api_key!
    assert_equal %w[lock], actions_of('account_locks', user)
    run_action('account_locks', user, 'lock')
    assert_equal 200, response.status
    user.reload
    assert user.locked_at.present?
    assert_nil user.spree_api_key, 'the api key is cleared'
    assert_equal %w[unlock], actions_of('account_locks', user)
    run_action('account_locks', user, 'unlock')
    assert_equal 200, response.status
    assert_nil user.reload.locked_at

    other_admin = admin_user
    assert_equal [], actions_of('account_locks', other_admin)
    run_action('account_locks', other_admin, 'lock')
    assert_equal 422, response.status
    assert_nil other_admin.reload.locked_at

    body = call(:get, "/account_locks/#{user.id}")
    assert_equal %w[email locked_at created_at].sort, body.dig('data', 'values').keys.sort
  end

  test 'profiles are hidden and shown again' do
    profile = sample('user_profiles')
    assert_equal %w[hide], actions_of('user_profiles', profile)
    run_action('user_profiles', profile, 'hide')
    assert_equal 200, response.status
    assert_equal 'Hidden by an admin', profile.reload.hidden_reason
    run_action('user_profiles', profile, 'hide')
    assert_equal 422, response.status
    run_action('user_profiles', profile, 'unhide')
    assert_equal 200, response.status
    refute profile.reload.hidden?
  end

  # --- Commerce extras -------------------------------------------------------------------------

  test 'affiliates move through review as in the admin' do
    account = sample('affiliate_accounts')
    assert_equal %w[approve reject], actions_of('affiliate_accounts', account)
    call(:patch, "/affiliate_accounts/#{account.id}", { commission_bps: 1500, code: 'hijacked', status: 'approved' })
    assert_equal 200, response.status, response.body
    assert_equal [1500, 'pending'], [account.reload.commission_bps, account.status]
    refute_equal 'hijacked', account.code

    run_action('affiliate_accounts', account, 'approve')
    assert_equal 200, response.status
    assert_equal ['approved', @admin.id], [account.reload.status, account.reviewed_by_id]
    assert account.approved_at.present?
    run_action('affiliate_accounts', account, 'reject')
    assert_equal 422, response.status
    run_action('affiliate_accounts', account, 'suspend')
    assert_equal 200, response.status
    assert account.reload.suspended?
    run_action('affiliate_accounts', account, 'reinstate')
    assert_equal 200, response.status
    assert account.reload.approved?

    rejected = sample('affiliate_accounts')
    run_action('affiliate_accounts', rejected, 'reject')
    assert_equal 200, response.status
    assert_equal %w[approve], actions_of('affiliate_accounts', rejected)
  end

  test 'affiliate commissions are voided only while unpaid' do
    commission = sample('affiliate_commissions')
    run_action('affiliate_commissions', commission, 'void')
    assert_equal 200, response.status
    assert_equal %w[void admin], [commission.reload.state, commission.void_reason]
    run_action('affiliate_commissions', commission, 'void')
    assert_equal 422, response.status
  end

  test 'digital asset drafts are published, then retired' do
    asset = sample('digital_assets')
    run_action('digital_assets', asset, 'publish')
    assert_equal 422, response.status, 'a draft without files is not published'
    assert asset.reload.draft?

    asset.attach_files!([digital_blob])
    body = run_action('digital_assets', asset, 'publish')
    assert_equal 200, response.status, response.body
    assert_equal 'Published version 1.', body['message']
    assert asset.reload.published?
    assert_equal %w[retire], body.dig('data', 'actions')
    run_action('digital_assets', asset, 'retire')
    assert_equal 200, response.status
    assert asset.reload.retired?
  end

  test 'digital ownerships are revoked once' do
    ownership = sample('digital_ownerships')
    run_action('digital_ownerships', ownership, 'revoke')
    assert_equal 200, response.status
    assert_equal 'admin_revoked', ownership.reload.revoke_reason
    run_action('digital_ownerships', ownership, 'revoke')
    assert_equal 422, response.status
  end

  test 'in-app products are managed, purchases are not' do
    skip 'this app has no in-app purchases' unless TYPES.include?('iap_products')

    body = call(:post, '/iap_products', { platform: 'google', product_id: 'example.pro.monthly', kind: 'subscription',
                                          entitlement: 'pro', active: true })
    assert_equal 201, response.status, response.body
    call(:post, '/iap_products', { platform: 'google', product_id: 'example.pro.monthly', kind: 'subscription' })
    assert_equal 422, response.status
    call(:delete, "/iap_products/#{body.dig('data', 'id')}")
    assert_equal 204, response.status

    transaction = sample('iap_transactions')
    body = call(:get, "/iap_transactions/#{transaction.id}")
    refute body.dig('data', 'values').key?('account_token')
    refute body.dig('data', 'values').key?('signed_payload')
  end

  test 'content images show their file and edit their text' do
    skip 'this app has no content images' unless TYPES.include?('content_assets')

    asset = sample('content_assets')
    body = call(:get, "/content_assets/#{asset.id}")
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/}, body.dig('data', 'values', 'file')
    call(:patch, "/content_assets/#{asset.id}", { alt_text: 'Updated alt', byte_size: 1 })
    assert_equal 200, response.status, response.body
    assert_equal 'Updated alt', asset.reload.alt_text
    refute_equal 1, asset.byte_size
  end

  test 'product videos show their poster and video' do
    video = sample('product_videos')
    body = call(:get, "/product_videos/#{video.id}")
    assert_match %r{/rails/active_storage/blobs/}, body.dig('data', 'values', 'poster')
    assert_match %r{/rails/active_storage/blobs/}, body.dig('data', 'values', 'video_url')
    call(:delete, "/product_videos/#{video.id}")
    assert_equal 204, response.status
  end

  # --- Action inputs ---------------------------------------------------------------------------

  def granting_purchase(user, key: 'pro')
    product = create(:iap_product, entitlement: key)
    transaction = create(:iap_transaction, user: user, iap_product: product, product_id: product.product_id)
    EntitlementResolver.refresh(user)
    transaction
  end

  test 'entitlements are revoked with a required note, through every purchase that grants them' do
    skip 'this app has no in-app purchases' unless TYPES.include?('entitlements')

    user = create(:iap_user)
    purchase = granting_purchase(user)
    entitlement = Spree::Entitlement.find_by!(user_id: user.id, key: 'pro')
    assert entitlement.current?
    assert_equal %w[revoke], actions_of('entitlements', entitlement)

    body = run_action('entitlements', entitlement, 'revoke')
    assert_equal 422, response.status
    assert_equal ["can't be blank"], body.dig('error', 'fields', 'note')
    assert_equal 'active', purchase.reload.status

    body = run_action('entitlements', entitlement, 'revoke', { note: 'Chargeback' })
    assert_equal 200, response.status, response.body
    assert_equal 'Entitlement pro revoked.', body['message']
    assert_equal 'revoked', purchase.reload.status
    assert purchase.admin_revoked_at.present?
    log = purchase.audit_logs.last
    assert_equal ['revoke', 'Chargeback', @admin.id], [log.action, log.note, log.admin_user_id]
    refute Spree::Entitlement.current_for(user, 'pro')

    run_action('entitlements', entitlement, 'revoke', { note: 'Again' })
    assert_equal 422, response.status, 'no longer current'

    orphan = Spree::Entitlement.create!(user: create(:iap_user), key: 'pro', active: true)
    body = run_action('entitlements', orphan, 'revoke', { note: 'No purchase' })
    assert_equal 422, response.status
    assert_includes body.dig('error', 'message'), 'No purchase currently grants this entitlement'
  end

  test 'in-app purchases are revoked once, with a required note' do
    skip 'this app has no in-app purchases' unless TYPES.include?('iap_transactions')

    user = create(:iap_user)
    purchase = granting_purchase(user)
    assert_equal %w[revoke], actions_of('iap_transactions', purchase)
    body = run_action('iap_transactions', purchase, 'revoke', { note: '' })
    assert_equal 422, response.status
    assert_equal ["can't be blank"], body.dig('error', 'fields', 'note')
    assert_nil purchase.reload.admin_revoked_at

    body = run_action('iap_transactions', purchase, 'revoke', { note: 'Refunded by support' })
    assert_equal 200, response.status, response.body
    assert_equal 'Purchase revoked.', body['message']
    assert_equal [], body.dig('data', 'actions')
    assert_equal ['revoked', 'Refunded by support'], [purchase.reload.status, purchase.audit_logs.last.note]
    refute Spree::Entitlement.current_for(user, 'pro')
    run_action('iap_transactions', purchase, 'revoke', { note: 'Again' })
    assert_equal 422, response.status
  end

  test 'creator payouts are recorded on the creator with a reference' do
    account = create(:creator_account)
    assert_equal [], actions_of('creator_accounts', account) - %w[suspend revoke], 'nothing payable yet'
    create(:creator_earning, creator_account: account, amount: 7, payable_at: 1.day.ago)
    create(:creator_earning, creator_account: account, amount: 3.5, state: 'payable', payable_at: 2.days.ago)
    held = create(:creator_earning, creator_account: account, amount: 100)
    assert_includes actions_of('creator_accounts', account), 'record_payout'
    action = manifest_of('creator_accounts')['actions'].find { |a| a['name'] == 'record_payout' }
    assert_equal [%w[reference string], %w[currency string], %w[note text]], action['inputs'].map { |i| [i['name'], i['type']] }

    body = run_action('creator_accounts', account, 'record_payout', { note: 'Wire' })
    assert_equal 422, response.status
    assert_equal ["can't be blank"], body.dig('error', 'fields', 'reference')
    assert_equal 0, Spree::CreatorPayout.where(creator_account: account).count

    body = run_action('creator_accounts', account, 'record_payout', { reference: 'WIRE-42', note: 'March' })
    assert_equal 200, response.status, response.body
    assert_equal 'Payout of 10.50 USD recorded.', body['message']
    payout = Spree::CreatorPayout.find_by!(creator_account: account)
    assert_equal [BigDecimal('10.5'), 'USD', 'WIRE-42', 'March'], [payout.amount, payout.currency, payout.reference, payout.note]
    assert_equal %w[paid paid], Spree::CreatorEarning.where(creator_payout_id: payout.id).pluck(:state)
    assert held.reload.pending?
    refute_includes body.dig('data', 'actions'), 'record_payout'

    run_action('creator_accounts', account, 'record_payout', { reference: 'WIRE-43' })
    assert_equal 422, response.status, 'nothing left to pay'
    create(:creator_earning, creator_account: account, state: 'payable', payable_at: 1.day.ago)
    body = run_action('creator_accounts', account, 'record_payout', { reference: 'WIRE-44', currency: 'eur' })
    assert_equal 422, response.status
    assert_includes body.dig('error', 'message'), 'Nothing is payable in EUR'
  end

  test 'affiliate payouts are recorded on the affiliate with a reference' do
    account = create(:affiliate_account, :approved)
    refute_includes actions_of('affiliate_accounts', account), 'record_payout'
    commission = create(:affiliate_commission, affiliate_account: account, state: 'approved', amount: 12)
    assert_includes actions_of('affiliate_accounts', account), 'record_payout'

    body = run_action('affiliate_accounts', account, 'record_payout', { reference: ' ' })
    assert_equal 422, response.status
    assert_equal ["can't be blank"], body.dig('error', 'fields', 'reference')

    body = run_action('affiliate_accounts', account, 'record_payout', { reference: 'PP-7' })
    assert_equal 200, response.status, response.body
    assert_equal "Payout of 12.00 #{commission.currency} recorded.", body['message']
    assert_equal 'paid', commission.reload.state
    assert_equal 'PP-7', commission.payout.reference
    run_action('affiliate_accounts', account, 'record_payout', { reference: 'PP-8' })
    assert_equal 422, response.status
  end

  test 'review decisions take the admin notes and overrides' do
    account = sample('affiliate_accounts')
    call(:patch, "/affiliate_accounts/#{account.id}", { commission_bps: 2500 })
    assert_equal 200, response.status, response.body
    run_action('affiliate_accounts', account, 'approve', { note: 'Big audience', unknown: 'ignored' })
    assert_equal 200, response.status, response.body
    assert_equal ['approved', 2500, 'Big audience'], [account.reload.status, account.commission_bps, account.review_note]
    run_action('affiliate_accounts', account, 'suspend')
    assert_equal ['suspended', 2500, 'Big audience'], [account.reload.status, account.commission_bps, account.review_note]

    application = sample('creator_applications')
    run_action('creator_applications', application, 'reject', { note: 'Samples too short' })
    assert_equal 200, response.status
    assert_equal ['rejected', 'Samples too short'], [application.reload.status, application.review_note]

    report = sample('content_reports')
    run_action('content_reports', report, 'hide_profile', { note: 'Spam links' })
    assert_equal 200, response.status, response.body
    assert_equal 'Profile hidden: Spam links', report.reload.resolution_note
    assert_equal "Report ##{report.id}: Spam links", report.reportable.reload.hidden_reason
    dismissed = sample('content_reports')
    run_action('content_reports', dismissed, 'dismiss', { note: 'Not spam' })
    assert_equal ['dismissed', 'Not spam'], [dismissed.reload.status, dismissed.resolution_note]

    profile = sample('user_profiles')
    hide = manifest_of('user_profiles')['actions'].find { |a| a['name'] == 'hide' }
    assert_equal 'Hidden by an admin', hide['inputs'].first['default']
    run_action('user_profiles', profile, 'hide', { reason: 'Impersonation' })
    assert_equal 'Impersonation', profile.reload.hidden_reason

    ownership = sample('digital_ownerships')
    run_action('digital_ownerships', ownership, 'revoke', { reason: 'refund' })
    assert_equal 200, response.status
    assert_equal 'refund', ownership.reload.revoke_reason
  end

  # --- References, uploads, filters, versions ---------------------------------------------------

  test 'user, product, variant and order ids come back with titles from the built-in lookups' do
    lookups = call(:get, '')['data'].select { |type| type['key'].start_with?('spree_') }
    assert_equal %w[spree_orders spree_products spree_taxons spree_users spree_variants], lookups.map { |t| t['key'] }.sort
    assert lookups.all? { |t| t['hidden'] }
    resources = call(:get, '')['data'].flat_map { |t| t['fields'].select { |f| f['type'] == 'reference' }.map { |f| f['resource'] } }
    assert_includes resources, 'spree_users'

    ownership = sample('digital_ownerships')
    user = ownership.user
    sample('digital_ownerships')
    body = call(:get, "/digital_ownerships?filter[user_id]=#{user.id}")
    assert_equal [ownership.id], ids_of(body)
    assert_equal({ 'id' => user.id.to_s, 'title' => user.email }, body['data'].first.dig('values', 'user_id'))
    assert_equal ownership.variant.sku.presence || "##{ownership.variant_id}", body['data'].first.dig('values', 'variant_id', 'title')

    if TYPES.include?('entitlements')
      buyer = create(:iap_user)
      granting_purchase(buyer)
      body = call(:get, "/entitlements?filter[user_id]=#{buyer.id}")
      assert_equal Spree::Entitlement.where(user_id: buyer.id).pluck(:id), ids_of(body)
      assert_equal({ 'id' => buyer.id.to_s, 'title' => buyer.email }, body['data'].first.dig('values', 'user_id'))
    end

    video = sample('product_videos')
    body = call(:get, "/product_videos/#{video.id}")
    assert_equal({ 'id' => video.product_id.to_s, 'title' => video.product.name }, body.dig('data', 'values', 'product_id'))

    commission = sample('affiliate_commissions')
    body = call(:get, "/affiliate_commissions/#{commission.id}")
    assert_equal({ 'id' => commission.order_id.to_s, 'title' => commission.order.number }, body.dig('data', 'values', 'order_id'))
    assert_equal "10.00 #{commission.currency}", body.dig('data', 'title')

    account = sample('creator_accounts')
    body = call(:get, "/creator_accounts/#{account.id}")
    assert_equal account.user.email, body.dig('data', 'title')
    assert_equal account.user.email, body.dig('data', 'values', 'user_id', 'title')

    body = call(:get, "/spree_users?q=#{CGI.escape(user.email)}")
    assert_equal [user.id], ids_of(body)
    call(:post, '/spree_users', { email: 'new@example.com' })
    assert_equal 403, response.status, 'lookups are read-only'
  end

  test 'content images are uploaded, created and replaced from the app' do
    skip 'this app has no content images' unless TYPES.include?('content_assets')

    blob = upload
    assert_equal %w[byte_size content_type filename signed_id url], blob.keys.sort
    body = call(:post, '/content_assets', { file: blob['signed_id'], alt_text: 'Hero', tag: 'Banners' })
    assert_equal 201, response.status, response.body
    asset = ContentAsset.find(body.dig('data', 'id'))
    assert asset.file.attached?
    assert_equal ['test-image.png', 'image/png', 'banners'], [asset.reload.original_filename, asset.content_type, asset.tag]
    assert_match %r{/rails/active_storage/blobs/}, body.dig('data', 'values', 'file')

    call(:post, '/content_assets', { alt_text: 'No file' })
    assert_equal 422, response.status, 'a new image needs a file'
    body = call(:post, '/content_assets', { file: 'not-a-signed-id' })
    assert_equal 422, response.status
    assert_includes body.dig('error', 'fields', 'file'), 'is not a valid upload'
    text = upload(Rack::Test::UploadedFile.new(StringIO.new('just text'), 'text/plain', original_filename: 'notes.txt'))
    body = call(:post, '/content_assets', { file: text['signed_id'] })
    assert_equal 422, response.status, 'ContentAsset checks the type'
    assert body.dig('error', 'fields', 'file').any?

    replacement = upload('avatar.png', 'image/png')
    call(:patch, "/content_assets/#{asset.id}", { file: replacement['signed_id'] })
    assert_equal 200, response.status, response.body
    assert_equal 'avatar.png', asset.reload.file.filename.to_s
    call(:patch, "/content_assets/#{asset.id}", { file: nil })
    assert_equal 422, response.status, 'a content image keeps its file'
  end

  test 'posters, the theme logo and favicon are uploaded; feedback screenshots and photos are not' do
    video = sample('product_videos')
    poster = upload('avatar.png', 'image/png')
    call(:patch, "/product_videos/#{video.id}", { poster: poster['signed_id'], alt: 'New poster' })
    assert_equal 200, response.status, response.body
    assert_equal ['avatar.png', 'New poster'], [video.reload.poster.filename.to_s, video.alt]
    call(:patch, "/product_videos/#{video.id}", { poster: nil })
    assert_equal 422, response.status, 'ProductVideo needs a poster'

    theme = sample('admin_theme')
    logo = upload
    body = call(:patch, "/admin_theme/#{theme.id}", { logo: logo['signed_id'], favicon: upload['signed_id'] })
    assert_equal 200, response.status, response.body
    assert theme.reload.logo.attached? && theme.favicon.attached?
    assert_match %r{/rails/active_storage/blobs/}, body.dig('data', 'values', 'logo')
    body = call(:patch, "/admin_theme/#{theme.id}", { logo: nil })
    assert_equal 200, response.status, response.body
    assert_nil body.dig('data', 'values', 'logo')
    refute theme.reload.logo.attached?

    feedback = sample('app_feedback')
    feedback.screenshot.attach(io: StringIO.new(PNG_BYTES), filename: 'shot.png', content_type: 'image/png')
    before = feedback.screenshot.blob_id
    call(:patch, "/app_feedback/#{feedback.id}", { screenshot: upload['signed_id'], status: 'triaged' })
    assert_equal 200, response.status
    feedback.reload
    assert_equal before, feedback.screenshot.blob_id, 'a screenshot is never replaced'
    assert_equal 'triaged', feedback.status
    readonly = %w[app_feedback user_profiles].map do |key|
      manifest_of(key)['fields'].find { |f| f['type'] == 'image' }['readonly']
    end
    assert_equal [true, true], readonly
  end

  test 'uploads need an admin and a file' do
    post "#{BASE}/uploads", params: { file: fixture_file_upload('test-image.png', 'image/png') }
    assert_equal 401, response.status
    post "#{BASE}/uploads", headers: { 'X-Spree-Token' => @admin.spree_api_key }
    assert_equal 422, response.status
  end

  test 'filters by presence, date range and reference' do
    locked = create(:user)
    Profiles::Moderation.lock(locked)
    open_account = create(:user)
    filters = manifest_of('account_locks')['filters']
    assert_equal({ 'name' => 'locked_at', 'label' => 'Locked at', 'type' => 'presence', 'options' => %w[set unset] }, filters.first)
    set = ids_of(call(:get, '/account_locks?filter[locked_at]=set&per_page=100'))
    assert_includes set, locked.id
    refute_includes set, open_account.id
    unset = ids_of(call(:get, '/account_locks?filter[locked_at]=unset&per_page=100'))
    assert_includes unset, open_account.id
    refute_includes unset, locked.id

    old = sample('content_reports')
    old.update_columns(created_at: 10.days.ago)
    recent = sample('content_reports')
    assert_equal 'date_range', manifest_of('content_reports')['filters'].find { |f| f['name'] == 'created_at' }['type']
    from = 2.days.ago.to_date.iso8601
    ids = ids_of(call(:get, "/content_reports?filter[created_at][from]=#{from}&per_page=100"))
    assert_includes ids, recent.id
    refute_includes ids, old.id
    ids = ids_of(call(:get, "/content_reports?filter[created_at][to]=#{3.days.ago.to_date.iso8601}&per_page=100"))
    assert_equal [old.id], ids

    payout = sample('creator_payouts')
    payout.update_columns(paid_at: 40.days.ago)
    ids = ids_of(call(:get, "/creator_payouts?filter[paid_at][from]=#{1.week.ago.to_date.iso8601}"))
    refute_includes ids, payout.id
    ids = ids_of(call(:get, "/creator_payouts?filter[creator_account_id]=#{payout.creator_account_id}"))
    assert_equal [payout.id], ids

    location = sample('menu_locations')
    item = MenuItem.create!(name: 'Here', menu_location: location)
    other = sample('menu_items')
    filter = manifest_of('menu_items')['filters'].find { |f| f['name'] == 'menu_location_id' }
    assert_equal %w[reference menu_locations], [filter['type'], filter['resource']]
    ids = ids_of(call(:get, "/menu_items?filter[menu_location_id]=#{location.id}&per_page=100"))
    assert_includes ids, item.id
    refute_includes ids, other.id
  end

  test 'labels, defaults and inferred required fields' do
    assert_equal 'Account', manifest_of('account_locks')['singular']
    assert_equal 'Product in review', manifest_of('creator_reviews')['singular']
    assert_equal 'Menu item', manifest_of('menu_items')['singular']
    fields = manifest_of('app_settings')['fields'].index_by { |f| f['name'] }
    assert_equal AppSetting::DEFAULT_NAME, fields['name']['default']
    fields = manifest_of('push_notifications')['fields'].index_by { |f| f['name'] }
    assert_equal %w[custom all], [fields['notification_type']['default'], fields['target']['default']]
    assert fields['title']['required']
    fields = manifest_of('homepage_sections')['fields'].index_by { |f| f['name'] }
    assert_equal true, fields['is_visible']['default']
    refute fields['position']['required'], 'HomepageSection puts a blank position last'
    assert manifest_of('menu_items')['fields'].find { |f| f['name'] == 'name' }['required']
  end

  test 'an edit based on an old version is refused' do
    location = sample('menu_locations')
    version = call(:get, "/menu_locations/#{location.id}").dig('data', 'version')
    assert version.present?
    call(:patch, "/menu_locations/#{location.id}", { title: 'First' }, @admin.spree_api_key, version: version)
    assert_equal 200, response.status, response.body
    body = call(:patch, "/menu_locations/#{location.id}", { title: 'Second' }, @admin.spree_api_key, version: version)
    assert_equal 409, response.status
    assert_equal 'conflict', body.dig('error', 'code')
    assert_equal 'First', location.reload.title
  end
end
