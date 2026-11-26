require 'test_helper'

# Admin "Creators" tab: applications, accounts and the product review queue. Admins only.
class Spree::Admin::CreatorsAdminTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    digital_store
    @marketplace, @packs = marketplace_taxons
    @admin = admin_user
    @application = create(:creator_application, display_name: 'Pending Person',
                                                sample_upload_signed_ids: [digital_blob(DigitalAssetsTestHelper::WAV_BYTES, 'demo.wav').signed_id])
    @creator = creator_user
    @product = creator_product(@creator, taxons: [@packs])
    @product.update!(review_state: 'submitted', submitted_at: Time.current)
  end

  teardown { Warden.test_reset! }

  def sign_in(user)
    login_as(user, scope: :spree_user)
  end

  test 'non-admins cannot see or change anything' do
    sign_in(create(:user))
    get '/admin/creator_applications'
    refute_includes response.body, 'Pending Person'
    post "/admin/creator_applications/#{@application.id}/approve"
    assert @application.reload.pending?
    post "/admin/creator_reviews/#{@product.id}/approve"
    assert_equal 'submitted', @product.reload.review_state
    patch "/admin/creator_accounts/#{Spree::CreatorAccount.last.id}", params: { creator_account: { revenue_share_bps: 9999 } }
    refute_equal 9999, Spree::CreatorAccount.last.revenue_share_bps
  end

  test 'the sidebar has a Creators tab' do
    sign_in(@admin)
    get '/admin/creator_applications'
    assert_response :success
    assert_includes response.body, 'sidebarCreators'
    refute_includes response.body, 'dna-modern'
  end

  test 'applications filter by status and show the demo files' do
    sign_in(@admin)
    get '/admin/creator_applications', params: { status: 'pending' }
    assert_response :success
    assert_includes response.body, 'Pending Person'

    get '/admin/creator_applications', params: { status: 'rejected' }
    refute_includes response.body, 'Pending Person'

    get "/admin/creator_applications/#{@application.id}"
    assert_response :success
    assert_includes response.body, 'demo.wav'
    assert_includes response.body, '<audio'
  end

  test 'approve and reject applications with a note' do
    sign_in(@admin)
    post "/admin/creator_applications/#{@application.id}/approve", params: { review_note: 'Welcome' }
    assert_redirected_to "/admin/creator_applications/#{@application.id}"
    assert @application.reload.approved?
    assert Creators.creator?(@application.user.reload)

    other = create(:creator_application)
    post "/admin/creator_applications/#{other.id}/reject", params: { review_note: 'Not yet' }
    assert other.reload.rejected?
    assert_equal 'Not yet', other.review_note
  end

  test 'accounts: revenue share, suspend, reinstate and revoke' do
    sign_in(@admin)
    account = Spree::CreatorAccount.find_by(user_id: @creator.id)
    get '/admin/creator_accounts'
    assert_response :success
    assert_includes response.body, @creator.email

    patch "/admin/creator_accounts/#{account.id}", params: { creator_account: { revenue_share_bps: 8000, payout_email: 'pay@example.com' } }
    assert_equal 8000, account.reload.revenue_share_bps
    assert_equal 'pay@example.com', account.payout_email

    patch "/admin/creator_accounts/#{account.id}", params: { creator_account: { revenue_share_bps: 20_000 } }
    assert_equal 8000, account.reload.revenue_share_bps

    post "/admin/creator_accounts/#{account.id}/suspend"
    assert account.reload.suspended?
    post "/admin/creator_accounts/#{account.id}/reinstate"
    assert account.reload.active?

    post "/admin/creator_accounts/#{account.id}/revoke"
    refute Creators.creator?(@creator.reload)
    assert account.reload.suspended?
  end

  test 'review queue lists submitted products with players and the manifest' do
    sign_in(@admin)
    get '/admin/creator_reviews'
    assert_response :success
    assert_includes response.body, @product.name

    get "/admin/creator_reviews/#{@product.id}"
    assert_response :success
    assert_includes response.body, 'kick.wav'
    assert_includes response.body, '<audio'
    assert_includes response.body, '&quot;format&quot;'
  end

  test 'review queue approve, request changes and reject' do
    sign_in(@admin)
    post "/admin/creator_reviews/#{@product.id}/approve", params: { review_note: 'Nice' }
    assert_redirected_to '/admin/creator_reviews'
    assert_equal 'approved', @product.reload.review_state
    assert @product.available?

    second = creator_product(@creator)
    second.update!(review_state: 'submitted')
    post "/admin/creator_reviews/#{second.id}/request_changes", params: { review_note: 'Shorter tails' }
    assert_equal 'changes_requested', second.reload.review_state
    assert_equal 'Shorter tails', second.review_note

    third = creator_product(@creator)
    third.update!(review_state: 'submitted')
    post "/admin/creator_reviews/#{third.id}/reject", params: { review_note: '' }
    assert_equal 'submitted', third.reload.review_state
    post "/admin/creator_reviews/#{third.id}/reject", params: { review_note: 'Not original' }
    assert_equal 'rejected', third.reload.review_state
  end
end
