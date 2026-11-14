require 'test_helper'

# Admin "Affiliates" tab: applications and accounts, commissions, payouts. Admins only.
class Spree::Admin::AffiliatesControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    affiliate_store
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @pending = create(:affiliate_account, code: 'pending-one', application: { 'website' => 'https://pending.example.com',
                                                                              'message' => 'Let me in' })
    @approved = approved_affiliate(code: 'approved-one')
  end

  teardown { Warden.test_reset! }

  def sign_in(user)
    login_as(user, scope: :spree_user)
  end

  test 'non-admins cannot see or change anything' do
    get '/admin/affiliate_accounts'
    refute_includes response.body, 'pending-one'

    sign_in(create(:user))
    get '/admin/affiliate_accounts'
    refute_includes response.body, 'pending-one'
    post "/admin/affiliate_accounts/#{@pending.id}/approve"
    assert @pending.reload.pending?
    commission = create(:affiliate_commission, affiliate_account: @approved, state: 'approved')
    post "/admin/affiliate_commissions/#{commission.id}/void"
    assert_equal 'approved', commission.reload.state
    post '/admin/affiliate_payouts', params: { affiliate_account_id: @approved.id, reference: 'X' }
    assert_equal 0, AffiliatePayout.count
  end

  test 'the sidebar has an Affiliates tab for admins' do
    sign_in(@admin)
    get '/admin/affiliate_accounts'
    assert_response :success
    assert_includes response.body, 'sidebarAffiliates'
  end

  test 'applications list filters by status' do
    sign_in(@admin)
    get '/admin/affiliate_accounts', params: { status: 'pending' }
    assert_response :success
    assert_includes response.body, 'pending-one'
    refute_includes response.body, 'approved-one'

    get '/admin/affiliate_accounts'
    assert_includes response.body, 'pending-one'
    assert_includes response.body, 'approved-one'
  end

  test 'show displays the application' do
    sign_in(@admin)
    get "/admin/affiliate_accounts/#{@pending.id}"
    assert_response :success
    assert_includes response.body, 'https://pending.example.com'
    assert_includes response.body, 'Let me in'
  end

  test 'show renders for approved and suspended accounts with their commissions' do
    sign_in(@admin)
    order = complete_order!(cart_order)
    create(:affiliate_commission, affiliate_account: @approved, order: order, state: 'approved', amount: 4)
    get "/admin/affiliate_accounts/#{@approved.id}"
    assert_response :success
    assert_includes response.body, order.number
    assert_includes response.body, 'affiliate_suspend'
    assert_includes response.body, 'Record a payout'

    @approved.update!(status: 'suspended')
    get "/admin/affiliate_accounts/#{@approved.id}"
    assert_response :success
    assert_includes response.body, 'affiliate_reinstate'
  end

  test 'admin approve sets approved_at, reviewer and commission override' do
    sign_in(@admin)
    post "/admin/affiliate_accounts/#{@pending.id}/approve", params: { commission_bps: '1500', review_note: 'Welcome' }
    assert_redirected_to "/admin/affiliate_accounts/#{@pending.id}"
    @pending.reload
    assert @pending.approved?
    assert @pending.approved_at.present?
    assert_equal @admin.id, @pending.reviewed_by_id
    assert_equal 1500, @pending.commission_bps
    assert_equal 'Welcome', @pending.review_note
  end

  test 'admin approve with a blank override keeps the default rate' do
    sign_in(@admin)
    post "/admin/affiliate_accounts/#{@pending.id}/approve", params: { commission_bps: '' }
    assert_nil @pending.reload.commission_bps
    assert @pending.approved?
  end

  test 'admin reject, suspend and reinstate' do
    sign_in(@admin)
    post "/admin/affiliate_accounts/#{@pending.id}/reject", params: { review_note: 'Not a fit' }
    @pending.reload
    assert @pending.rejected?
    assert_equal 'Not a fit', @pending.review_note
    assert_nil @pending.approved_at

    post "/admin/affiliate_accounts/#{@approved.id}/suspend"
    assert @approved.reload.suspended?
    post "/admin/affiliate_accounts/#{@approved.id}/reinstate"
    assert @approved.reload.approved?
  end

  test 'admin updates terms' do
    sign_in(@admin)
    patch "/admin/affiliate_accounts/#{@approved.id}", params: { affiliate_account: { commission_bps: '2000', cookie_days: '60',
                                                                                      payout_email: 'new@example.com' } }
    @approved.reload
    assert_equal 2000, @approved.commission_bps
    assert_equal 60, @approved.cookie_days
    assert_equal 'new@example.com', @approved.payout_email
  end

  test 'commissions list filters by state and account, and void' do
    sign_in(@admin)
    pending = create(:affiliate_commission, affiliate_account: @approved, amount: 3)
    approved = create(:affiliate_commission, affiliate_account: @approved, state: 'approved', amount: 4)
    paid = create(:affiliate_commission, affiliate_account: @approved, state: 'paid', amount: 5)

    get '/admin/affiliate_commissions', params: { state: 'approved' }
    assert_response :success
    assert_includes response.body, "affiliate_commission_#{approved.id}"
    refute_includes response.body, "affiliate_commission_#{pending.id}"

    get '/admin/affiliate_commissions', params: { affiliate_account_id: @approved.id }
    assert_includes response.body, "affiliate_commission_#{paid.id}"

    post "/admin/affiliate_commissions/#{pending.id}/void"
    assert_equal 'void', pending.reload.state
    post "/admin/affiliate_commissions/#{paid.id}/void"
    assert_equal 'paid', paid.reload.state, 'a paid commission stays paid'
  end

  test 'admin payout marks approved commissions paid with reference' do
    sign_in(@admin)
    a = create(:affiliate_commission, affiliate_account: @approved, state: 'approved', amount: 4)
    b = create(:affiliate_commission, affiliate_account: @approved, state: 'pending', amount: 6, approvable_at: 1.hour.ago)
    later = create(:affiliate_commission, affiliate_account: @approved, state: 'pending', amount: 7)
    void = create(:affiliate_commission, affiliate_account: @approved, state: 'void', amount: 8)
    other = create(:affiliate_commission, affiliate_account: @pending, state: 'approved', amount: 9)

    get '/admin/affiliate_payouts/new', params: { affiliate_account_id: @approved.id }
    assert_response :success
    assert_includes response.body, '10.00'

    assert_difference -> { AffiliatePayout.count }, 1 do
      post '/admin/affiliate_payouts', params: { affiliate_account_id: @approved.id, reference: 'BANK-123', note: 'November' }
    end
    payout = AffiliatePayout.last
    assert_redirected_to '/admin/affiliate_payouts'
    assert_equal 10.0, payout.amount.to_f
    assert_equal 'USD', payout.currency
    assert_equal 'BANK-123', payout.reference
    assert payout.paid_at.present?
    assert_equal [a.id, b.id].sort, payout.commissions.pluck(:id).sort
    assert_equal %w[paid paid pending void approved], [a, b, later, void, other].map { |c| c.reload.state }

    get '/admin/affiliate_payouts'
    assert_response :success
    assert_includes response.body, 'BANK-123'
  end

  test 'a payout needs a reference and something to pay' do
    sign_in(@admin)
    post '/admin/affiliate_payouts', params: { affiliate_account_id: @approved.id, reference: 'NOTHING' }
    assert_equal 0, AffiliatePayout.count

    create(:affiliate_commission, affiliate_account: @approved, state: 'approved', amount: 4)
    post '/admin/affiliate_payouts', params: { affiliate_account_id: @approved.id, reference: '' }
    assert_equal 0, AffiliatePayout.count
  end
end
