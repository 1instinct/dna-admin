require 'test_helper'

# config/initializers/spree_admin_native_resources.rb: the admin types the Spree Admin Native app
# shows under More, read and changed through /api/admin_native/v1/resources with an admin API key.
class SpreeAdminNativeResourcesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BASE = '/api/admin_native/v1/resources'.freeze
  EXPO_URL = 'https://exp.host/--/api/v2/push/send'.freeze
  # The gem's own pattern plus the credentials this app keeps under other names.
  SECRET_LOOKING = /password|token|secret|digest|encrypted|api_key|salt|otp|private_key|credentials|stream_key|signed_payload/i.freeze
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
  def call(method, path, values = nil, api_key = @admin.spree_api_key)
    headers = { 'X-Spree-Token' => api_key, 'CONTENT_TYPE' => 'application/json' }
    send(method, "#{BASE}#{path}", params: values ? { values: values }.to_json : nil, headers: headers)
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def run_action(key, record, action)
    call(:post, "/#{key}/#{record.id}/actions/#{action}")
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
      assert model.method_defined?(type['title_field']), "#{type['key']} title #{type['title_field']}"
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

  test 'forks can change each type after it is registered' do
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
    item = call(:post, '/menu_items', { name: 'About', url: '/about', menu_location_id: location.dig('data', 'id') })
    assert_equal 201, response.status, response.body
    assert_equal({ 'id' => location.dig('data', 'id'), 'title' => 'Footer' }, item.dig('data', 'values', 'menu_location_id'))

    child = call(:post, '/menu_items', { name: 'Team', menu_location_id: location.dig('data', 'id'), parent_id: item.dig('data', 'id') })
    assert_equal 201, response.status, response.body
    call(:patch, "/menu_items/#{item.dig('data', 'id')}", { is_visible: false })
    assert_nil MenuItem.find(item.dig('data', 'id')).is_visible, 'is_visible is not in the admin permitted params'

    call(:delete, "/menu_items/#{item.dig('data', 'id')}")
    assert_equal 422, response.status, 'an item with children is kept'
    assert MenuItem.exists?(item.dig('data', 'id'))
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
    call(:patch, "/push_notifications/#{id}", { title: 'Rewritten' })
    assert_equal 422, response.status
    call(:delete, "/push_notifications/#{id}")
    assert_equal 422, response.status
    assert_equal 'Big sale', notification.reload.title
    assert_requested(:post, EXPO_URL, times: 1)
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
    assert_equal %w[approve], actions_of('creator_reviews', product)
    run_action('creator_reviews', product, 'reject')
    assert_equal 422, response.status, 'a rejection needs a note'
    assert_equal 'submitted', product.reload.review_state

    call(:patch, "/creator_reviews/#{product.id}", { review_note: 'Trim the intro', name: 'Renamed', review_state: 'approved' })
    assert_equal 200, response.status, response.body
    assert_equal ['submitted', 'Trim the intro'], [product.reload.review_state, product.review_note]
    refute_equal 'Renamed', product.name
    assert_equal %w[approve request_changes reject], actions_of('creator_reviews', product)
    run_action('creator_reviews', product, 'request_changes')
    assert_equal 200, response.status, response.body
    assert_equal 'changes_requested', product.reload.review_state
    call(:get, "/creator_reviews/#{product.id}")
    assert_equal 404, response.status, 'a decided product leaves the queue'

    approved = sample('creator_reviews')
    run_action('creator_reviews', approved, 'approve')
    assert_equal 200, response.status, response.body
    assert_equal 'approved', approved.reload.review_state
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
end
