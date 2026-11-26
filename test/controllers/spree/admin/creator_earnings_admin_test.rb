require 'test_helper'

# Admin Creators tab: earnings and payouts.
class Spree::Admin::CreatorEarningsAdminTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = admin_user
    @creator = creator_user
    @account = Spree::CreatorAccount.find_by!(user_id: @creator.id)
    @due = create(:creator_earning, creator_account: @account, payable_at: 1.minute.ago, amount: 7)
    @later = create(:creator_earning, creator_account: @account, payable_at: 1.day.from_now, amount: 2)
  end

  teardown { Warden.test_reset! }

  test 'non-admins cannot pay out' do
    login_as(create(:user), scope: :spree_user)
    post '/admin/creator_payouts', params: { creator_account_id: @account.id, reference: 'X', currency: 'USD' }
    assert_equal 0, Spree::CreatorPayout.count
  end

  test 'earnings list sweeps and filters by state' do
    login_as(@admin, scope: :spree_user)
    get '/admin/creator_earnings', params: { state: 'payable' }
    assert_response :success
    assert_equal 'payable', @due.reload.state
    assert_includes response.body, "creator_earning_#{@due.id}"
    refute_includes response.body, "creator_earning_#{@later.id}"
    refute_includes response.body, 'dna-modern'
  end

  test 'admin voids an earning with reason admin' do
    login_as(@admin, scope: :spree_user)
    post "/admin/creator_earnings/#{@later.id}/void"
    assert_redirected_to '/admin/creator_earnings'
    assert_equal 'void', @later.reload.state
    assert_equal 'admin', @later.void_reason

    @due.update!(state: 'paid')
    post "/admin/creator_earnings/#{@due.id}/void"
    assert_equal 'paid', @due.reload.state
  end

  test 'payouts page lists payable balances and a payout marks them paid' do
    login_as(@admin, scope: :spree_user)
    get '/admin/creator_payouts'
    assert_response :success
    assert_includes response.body, @creator.email

    get '/admin/creator_payouts/new', params: { creator_account_id: @account.id }
    assert_response :success
    assert_includes response.body, '7.00'

    post '/admin/creator_payouts', params: { creator_account_id: @account.id, reference: 'BANK-9', note: 'Nov', currency: 'USD' }
    assert_redirected_to '/admin/creator_payouts'
    payout = Spree::CreatorPayout.last
    assert_equal 7.0, payout.amount.to_f
    assert_equal 'paid', @due.reload.state
    assert_equal payout.id, @due.creator_payout_id
    assert_equal 'pending', @later.reload.state

    post '/admin/creator_payouts', params: { creator_account_id: @account.id, reference: 'AGAIN', currency: 'USD' }
    assert_equal 1, Spree::CreatorPayout.count
  end
end
