require 'test_helper'

# Admin "Reports" tab: content reports, open first, with moderation actions.
class Spree::Admin::ContentReportsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include ActiveJob::TestHelper

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @reporter = create(:user)
    @target_user = create(:user)
    @profile = create(:user_profile, user: @target_user, handle: 'target', bio: 'bad bio')
    @report = Spree::ContentReport.for_profile(@profile, reporter: @reporter, reason: 'spam', details: 'ads')
    @report.save!
  end

  teardown { Warden.test_reset! }

  def sign_in(user)
    login_as(user, scope: :spree_user)
  end

  test 'admin only' do
    get '/admin/content_reports'
    refute_includes response.body, "content_report_#{@report.id}", 'anonymous gets the login page'

    sign_in(create(:user))
    get '/admin/content_reports'
    refute_includes response.body, "content_report_#{@report.id}"
    post "/admin/content_reports/#{@report.id}/hide_profile"
    assert_nil @profile.reload.hidden_at
  end

  test 'index defaults to open reports' do
    closed = Spree::ContentReport.for_profile(@profile, reporter: @reporter, reason: 'hate')
    closed.save!
    closed.resolve!(status: 'dismissed', by: @admin)

    sign_in(@admin)
    get '/admin/content_reports'
    assert_response :success
    assert_includes response.body, "content_report_#{@report.id}"
    refute_includes response.body, "content_report_#{closed.id}"

    get '/admin/content_reports', params: { status: 'all' }
    assert_includes response.body, "content_report_#{closed.id}"
  end

  test 'show renders the snapshot' do
    sign_in(@admin)
    get "/admin/content_reports/#{@report.id}"
    assert_response :success
    assert_includes response.body, 'bad bio'
    assert_includes response.body, '@target'
  end

  test 'dismiss' do
    sign_in(@admin)
    post "/admin/content_reports/#{@report.id}/dismiss", params: { resolution_note: 'fine' }
    assert_response :redirect
    @report.reload
    assert_equal 'dismissed', @report.status
    assert_equal @admin.id, @report.resolved_by_id
    assert @report.resolved_at.present?
    assert_equal 'fine', @report.resolution_note
  end

  test 'hide profile' do
    sign_in(@admin)
    post "/admin/content_reports/#{@report.id}/hide_profile", params: { resolution_note: 'spammer' }
    assert_response :redirect
    assert @profile.reload.hidden_at.present?
    assert_actioned
  end

  test 'remove photo' do
    @profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    blob = @profile.reload.avatar.blob
    sign_in(@admin)
    post "/admin/content_reports/#{@report.id}/remove_photo", params: { resolution_note: 'nsfw' }
    refute @profile.reload.avatar.attached?
    refute ActiveStorage::Blob.exists?(blob.id), 'purged at once, not by a job a restart can lose'
    refute blob.service.exist?(blob.key)
    assert_actioned
  end

  test 'clear bio' do
    sign_in(@admin)
    post "/admin/content_reports/#{@report.id}/clear_bio", params: { resolution_note: 'slur' }
    assert_nil @profile.reload.bio
    assert_actioned
  end

  test 'lock account: locked_at set, tokens revoked, password sign-in refused' do
    token = token_for(@target_user)
    sign_in(@admin)
    post "/admin/content_reports/#{@report.id}/lock_account", params: { resolution_note: 'ban' }
    assert @target_user.reload.locked_at.present?
    assert Doorkeeper.config.access_token_model.by_token(token).revoked?
    refute @target_user.valid_for_authentication? { true }
    assert_actioned

    post '/spree_oauth/token', params: { grant_type: 'password', username: @target_user.email, password: 'password123' }
    refute_equal 200, response.status
  end

  private

  def assert_actioned
    @report.reload
    assert_equal 'actioned', @report.status
    assert_equal @admin.id, @report.resolved_by_id
    assert @report.resolved_at.present?
    assert @report.resolution_note.present?
  end
end
