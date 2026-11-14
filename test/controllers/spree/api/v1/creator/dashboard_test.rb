require 'test_helper'

# GET /api/v1/creator, /api/v1/creator/sales and /api/v1/creator/payouts.
class Spree::Api::V1::Creator::DashboardTest < ActionDispatch::IntegrationTest
  setup do
    digital_store
    Spree::StockLocation.first || Spree::StockLocation.create!(name: 'Main', backorderable_default: true,
                                                                propagate_all_variants: true)
    @creator = creator_user(handle: 'nightshift', name: 'Night Shift')
    @account = Spree::CreatorAccount.find_by!(user_id: @creator.id)
    @headers = auth(@creator)
    @pack = approved_creator_product(@creator, price: 10)
    @preset = approved_creator_product(@creator, price: 5)
    @buyer = create(:user, email: 'buyer-secret@example.com')
    @order = complete_order!(cart_order(@buyer, [@pack, 2], [@preset, 1]))
  end

  test 'all endpoints 401 without bearer and 403 for non-creators' do
    %w[/api/v1/creator /api/v1/creator/sales /api/v1/creator/payouts].each do |path|
      get path
      assert_response :unauthorized
      get path, headers: auth(create(:user))
      assert_response :forbidden
    end
  end

  test 'show returns account, profile, totals and counts' do
    review = creator_product(@creator)
    review.update!(review_state: 'submitted')
    Spree::CreatorEarning.find_by!(line_item_id: @order.line_items.find_by!(variant_id: @preset.master.id).id)
                         .update!(payable_at: 1.minute.ago)

    get '/api/v1/creator', headers: @headers
    assert_response :success
    assert_equal({ 'revenue_share_bps' => 7000, 'payout_email' => 'payouts@example.com', 'status' => 'active' }.slice('revenue_share_bps', 'status'),
                 json['account'].slice('revenue_share_bps', 'status'))
    assert json['account'].key?('payout_email')
    assert_equal 'nightshift', json['profile']['handle']
    assert_equal 'Night Shift', json['profile']['name']
    assert json['profile'].key?('avatar_url')
    # The sweep on read made the preset's earning payable.
    assert_equal({ 'gross' => 25.0, 'earned' => 17.5, 'payable' => 3.5, 'paid' => 0.0, 'currency' => 'USD' }, json['totals'])
    assert_equal({ 'products_live' => 2, 'products_in_review' => 1, 'sales' => 3 }, json['counts'])
  end

  test 'sales series has one row per day with zeros and masked rows' do
    from = 2.days.ago.to_date
    get '/api/v1/creator/sales', headers: @headers, params: { from: from.iso8601, to: Date.current.iso8601 }
    assert_response :success
    assert_equal 3, json['series'].size
    assert_equal [from.iso8601, (from + 1).iso8601, Date.current.iso8601], json['series'].map { |row| row['date'] }
    assert_equal({ 'date' => from.iso8601, 'units' => 0, 'gross' => 0.0, 'earned' => 0.0 }, json['series'].first)
    assert_equal({ 'date' => Date.current.iso8601, 'units' => 3, 'gross' => 25.0, 'earned' => 17.5 }, json['series'].last)

    assert_equal 2, json['rows'].size
    row = json['rows'].detect { |r| r['product_id'] == @pack.id }
    assert_equal "****#{@order.number[-4..]}", row['order_masked']
    assert_equal 2, row['units']
    assert_equal 20.0, row['gross']
    assert_equal 14.0, row['earned']
    assert_equal 'pending', row['state']
    assert row['created_at']
    refute_includes response.body, @order.number
    refute_includes response.body, 'buyer-secret'
    json['rows'].each { |r| assert_equal %w[created_at earned gross order_masked product_id state units], r.keys.sort }
  end

  test 'sales filter by product, and never show another creator' do
    get '/api/v1/creator/sales', headers: @headers, params: { product_id: @preset.id }
    assert_equal [@preset.id], json['rows'].map { |r| r['product_id'] }
    assert_equal 1, json['series'].sum { |r| r['units'] }

    other = creator_user
    theirs = approved_creator_product(other, price: 7)
    complete_order!(cart_order(@buyer, [theirs, 1]))
    get '/api/v1/creator/sales', headers: @headers
    refute_includes json['rows'].map { |r| r['product_id'] }, theirs.id
    get '/api/v1/creator/sales', headers: @headers, params: { product_id: theirs.id }
    assert_response :not_found
  end

  test 'sales refuse bad ranges' do
    get '/api/v1/creator/sales', headers: @headers, params: { from: 'nope' }
    assert_response :unprocessable_entity
    get '/api/v1/creator/sales', headers: @headers, params: { from: '2026-01-01', to: '2025-01-01' }
    assert_response :unprocessable_entity
    get '/api/v1/creator/sales', headers: @headers, params: { from: '2020-01-01', to: '2026-01-01' }
    assert_response :unprocessable_entity
  end

  test 'void sales show in rows and not in the series' do
    @order.canceled_by(admin_user)
    get '/api/v1/creator/sales', headers: @headers
    assert_equal %w[void void], json['rows'].map { |r| r['state'] }
    assert_equal 0, json['series'].sum { |r| r['units'] }
  end

  test 'payouts lists own payouts newest first' do
    Spree::CreatorEarning.update_all(state: 'payable')
    payout = Creators::Payouts.create!(account: @account, reference: 'BANK-1', note: 'Nov', currency: 'USD')
    other_account = Spree::CreatorAccount.find_by!(user_id: creator_user.id)
    create(:creator_earning, creator_account: other_account, state: 'payable')
    Creators::Payouts.create!(account: other_account, reference: 'OTHER', currency: 'USD')

    get '/api/v1/creator/payouts', headers: @headers
    assert_response :success
    assert_equal 1, json['payouts'].size
    assert_equal({ 'id' => payout.id, 'amount' => 17.5, 'currency' => 'USD', 'reference' => 'BANK-1', 'note' => 'Nov' },
                 json['payouts'].first.except('paid_at'))
    assert json['payouts'].first['paid_at']
  end

  test 'product sales_count counts units sold' do
    get "/api/v1/creator/products/#{@pack.id}", headers: @headers
    assert_equal 2, json['sales_count']
  end
end
