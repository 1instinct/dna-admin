require 'test_helper'

# The signed-in user's affiliate account: apply, status, stats, commissions, payouts, code check.
class Spree::Api::V1::AffiliateControllerTest < ActionDispatch::IntegrationTest
  SHOW_KEYS = %w[status code link commission_bps cookie_days application totals payout_email].freeze
  TOTALS_KEYS = %w[clicks orders conversion pending approved paid currency].freeze

  setup do
    affiliate_store
    @user = create(:user)
    @headers = auth(@user)
    Affiliates.config.link_base_url = 'https://shop.example.com'
  end

  teardown { Affiliates.reset_config! }

  def json_headers(headers = @headers)
    headers.merge('CONTENT_TYPE' => 'application/json')
  end

  def apply(params, headers = @headers)
    post '/api/v1/affiliate', params: params.to_json, headers: json_headers(headers)
  end

  def application_params
    { website: 'https://maker.example.com', audience: 'Bedroom producers', channels: %w[youtube tiktok],
      message: 'I make tutorials', payout_email: 'pay@example.com' }
  end

  test 'all endpoints 401 without bearer' do
    get '/api/v1/affiliate'
    assert_response :unauthorized
    apply(application_params, {})
    assert_response :unauthorized
    patch '/api/v1/affiliate', params: { payout_email: 'x@example.com' }.to_json, headers: json_headers({})
    assert_response :unauthorized
    %w[stats commissions payouts code_available].each do |action|
      get "/api/v1/affiliate/#{action}"
      assert_response :unauthorized, action
    end
  end

  test 'show is 404 before applying' do
    get '/api/v1/affiliate', headers: @headers
    assert_response :not_found
  end

  test 'apply creates pending account with application jsonb' do
    apply(application_params.merge(code: 'Maker-Code'))
    assert_response :created
    assert_equal SHOW_KEYS.sort, json.keys.sort
    assert_equal TOTALS_KEYS.sort, json['totals'].keys.sort
    assert_equal 'pending', json['status']
    assert_equal 'maker-code', json['code']
    assert_equal 'https://shop.example.com/?ref=maker-code', json['link']
    assert_equal 1000, json['commission_bps']
    assert_equal 30, json['cookie_days']
    assert_equal({ 'website' => 'https://maker.example.com', 'audience' => 'Bedroom producers',
                   'channels' => %w[youtube tiktok], 'message' => 'I make tutorials' }, json['application'])
    assert_equal 'pay@example.com', json['payout_email']

    account = @user.reload.affiliate_account
    assert account.pending?
    assert_equal %w[youtube tiktok], account.application['channels']
  end

  test 'apply defaults the code to the profile handle' do
    create(:user_profile, user: @user, handle: 'loop_smith')
    apply(application_params)
    assert_response :created
    assert_equal 'loop-smith', json['code']
  end

  test 'apply twice is 422; a rejected applicant can apply again' do
    apply(application_params.merge(code: 'first-code'))
    assert_response :created
    apply(application_params.merge(code: 'second-code'))
    assert_response :unprocessable_entity

    @user.affiliate_account.update!(status: 'rejected', review_note: 'Not yet')
    apply(application_params.merge(code: 'second-code', message: 'Tried again'))
    assert_response :created
    assert_equal 'pending', json['status']
    assert_equal 'second-code', json['code']
    assert_equal 'Tried again', json['application']['message']
    assert_equal 1, AffiliateAccount.where(user_id: @user.id).count
  end

  test 'apply with a taken or invalid code is 422 with fields' do
    create(:affiliate_account, code: 'taken-code')
    apply(application_params.merge(code: 'taken-code'))
    assert_response :unprocessable_entity
    assert json['fields']['code'].present?

    apply(application_params.merge(code: 'no'))
    assert_response :unprocessable_entity
    assert json['fields']['code'].present?

    apply(application_params.merge(payout_email: 'not-an-email', code: 'fine-code'))
    assert_response :unprocessable_entity
    assert json['fields']['payout_email'].present?
  end

  test 'update changes the code only while pending, plus payout_email and application' do
    apply(application_params.merge(code: 'first-code'))
    patch '/api/v1/affiliate', params: { code: 'better-code', payout_email: 'new@example.com', message: 'Updated' }.to_json,
                               headers: json_headers
    assert_response :success
    assert_equal 'better-code', json['code']
    assert_equal 'new@example.com', json['payout_email']
    assert_equal 'Updated', json['application']['message']
    assert_equal 'https://maker.example.com', json['application']['website']

    @user.affiliate_account.update!(status: 'approved', approved_at: Time.current)
    patch '/api/v1/affiliate', params: { code: 'another-code' }.to_json, headers: json_headers
    assert_response :unprocessable_entity
    assert_equal 'better-code', @user.affiliate_account.reload.code

    patch '/api/v1/affiliate', params: { code: 'better-code', payout_email: 'later@example.com' }.to_json, headers: json_headers
    assert_response :success
    assert_equal 'later@example.com', json['payout_email']

    patch '/api/v1/affiliate', params: { payout_email: 'approved@example.com', website: 'https://new.example.com' }.to_json,
                               headers: json_headers
    assert_response :success
    get '/api/v1/affiliate', headers: @headers
    assert_equal 'approved', json['status']
    assert_equal 'approved@example.com', json['payout_email']
    assert_equal 'https://new.example.com', json['application']['website']
  end

  test 'update before applying is 404' do
    patch '/api/v1/affiliate', params: { payout_email: 'x@example.com' }.to_json, headers: json_headers
    assert_response :not_found
  end

  test 'code_available false for taken/reserved handles' do
    with_moderation_lists(reserved: %w[admin], blocked: %w[badword]) do
      create(:affiliate_account, code: 'taken-code')
      create(:user_profile, handle: 'other_maker')

      { 'taken-code' => false, 'admin' => false, 'other-maker' => false, 'x' => false, 'free-code' => true }.each do |code, expected|
        get '/api/v1/affiliate/code_available', params: { code: code }, headers: @headers
        assert_response :success
        assert_equal({ 'available' => expected }, json, code)
      end
    end
  end

  test 'code_available is true for the user\'s own code' do
    create(:affiliate_account, user: @user, code: 'mine-code')
    get '/api/v1/affiliate/code_available', params: { code: 'MINE-CODE' }, headers: @headers
    assert_equal({ 'available' => true }, json)
  end

  test 'show totals and lazy sweep' do
    account = create(:affiliate_account, :approved, user: @user, code: 'show-code', commission_bps: 1500)
    2.times { create(:affiliate_click, affiliate_account: account) }
    due = create(:affiliate_commission, affiliate_account: account, amount: 4, approvable_at: 1.hour.ago)
    create(:affiliate_commission, affiliate_account: account, amount: 6, approvable_at: 1.day.from_now)

    get '/api/v1/affiliate', headers: @headers
    assert_response :success
    assert_equal 'approved', json['status']
    assert_equal 1500, json['commission_bps']
    totals = json['totals']
    assert_equal 2, totals['clicks']
    assert_equal 2, totals['orders']
    assert_equal 1.0, totals['conversion']
    assert_equal 6.0, totals['pending']
    assert_equal 4.0, totals['approved']
    assert_equal 0.0, totals['paid']
    assert_equal 'USD', totals['currency']
    assert_equal 'approved', due.reload.state
  end

  test 'stats series has one row per day in range with zeros' do
    account = create(:affiliate_account, :approved, user: @user, code: 'stat-code')
    travel_to Time.zone.parse('2026-11-14 12:00') do
      @headers = auth(@user)
      create(:affiliate_click, affiliate_account: account, created_at: Time.zone.parse('2026-11-12 09:00'))
      create(:affiliate_click, affiliate_account: account, created_at: Time.zone.parse('2026-11-12 18:00'))
      create(:affiliate_commission, affiliate_account: account, amount: 3.5, created_at: Time.zone.parse('2026-11-13 10:00'))
      create(:affiliate_commission, affiliate_account: account, amount: 9, state: 'void',
                                    created_at: Time.zone.parse('2026-11-13 11:00'))

      get '/api/v1/affiliate/stats', params: { from: '2026-11-11', to: '2026-11-14' }, headers: @headers
      assert_response :success
      series = json['series']
      assert_equal %w[2026-11-11 2026-11-12 2026-11-13 2026-11-14], series.map { |r| r['date'] }
      assert_equal %w[clicks commission date orders], series.first.keys.sort
      assert_equal [0, 2, 0, 0], series.map { |r| r['clicks'] }
      assert_equal [0, 0, 1, 0], series.map { |r| r['orders'] }
      assert_equal [0.0, 0.0, 3.5, 0.0], series.map { |r| r['commission'] }

      get '/api/v1/affiliate/stats', headers: @headers
      assert_equal 30, json['series'].length
      assert_equal '2026-11-14', json['series'].last['date']

      get '/api/v1/affiliate/stats', params: { from: '2026-11-14', to: '2026-11-01' }, headers: @headers
      assert_response :unprocessable_entity
      get '/api/v1/affiliate/stats', params: { from: 'yesterday' }, headers: @headers
      assert_response :unprocessable_entity
      get '/api/v1/affiliate/stats', params: { from: '2024-01-01', to: '2026-11-14' }, headers: @headers
      assert_response :unprocessable_entity
    end
  end

  test 'commissions rows mask order number to last 4 chars and contain no email/name' do
    account = create(:affiliate_account, :approved, user: @user, code: 'rows-code')
    order = complete_order!(cart_order(email: 'secret.buyer@example.com'))
    order.update_columns(number: 'R555512345')
    create(:affiliate_commission, affiliate_account: account, order: order, base_amount: 50, amount: 5,
                                  approvable_at: Time.zone.parse('2026-12-14 10:00'))
    get '/api/v1/affiliate/commissions', headers: @headers
    assert_response :success
    assert_equal 1, json['page']
    assert_equal 1, json['pages']
    row = json['rows'].first
    assert_equal %w[amount approvable_at base_amount created_at order_masked state], row.keys.sort
    assert_equal '****2345', row['order_masked']
    assert_equal 50.0, row['base_amount']
    assert_equal 5.0, row['amount']
    assert_equal 'pending', row['state']
    refute_includes response.body, 'secret.buyer'
    refute_includes response.body, 'R555512345'
  end

  test 'commissions paginate 25 per page, newest first' do
    account = create(:affiliate_account, :approved, user: @user, code: 'page-code')
    other = create(:affiliate_account, :approved, code: 'other-code')
    create(:affiliate_commission, affiliate_account: other)
    26.times { |i| create(:affiliate_commission, affiliate_account: account, amount: i, created_at: i.minutes.ago) }

    get '/api/v1/affiliate/commissions', headers: @headers
    assert_equal 25, json['rows'].length
    assert_equal 2, json['pages']
    assert_equal 0.0, json['rows'].first['amount']

    get '/api/v1/affiliate/commissions', params: { page: 2 }, headers: @headers
    assert_equal 1, json['rows'].length
    assert_equal 2, json['page']
  end

  test 'payouts lists the account\'s payouts' do
    account = create(:affiliate_account, :approved, user: @user, code: 'paid-code')
    create(:affiliate_payout, affiliate_account: account, amount: 12.5, reference: 'PAY-9', note: 'Thanks')
    create(:affiliate_payout, affiliate_account: create(:affiliate_account, :approved, code: 'someone-else'))

    get '/api/v1/affiliate/payouts', headers: @headers
    assert_response :success
    assert_equal 1, json['payouts'].length
    payout = json['payouts'].first
    assert_equal %w[amount currency id paid_at reference], payout.keys.sort
    refute_includes response.body, 'Thanks', 'the payout note is internal'
    assert_equal 12.5, payout['amount']
    assert_equal 'PAY-9', payout['reference']
  end

  test 'stats, commissions and payouts are 404 before applying' do
    %w[stats commissions payouts].each do |action|
      get "/api/v1/affiliate/#{action}", headers: @headers
      assert_response :not_found, action
    end
  end
end
