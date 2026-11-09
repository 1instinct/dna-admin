require 'test_helper'

# Admin "Feedback" tab: filters, show page, triage and bulk archive, admins only.
class Spree::Admin::AppFeedbacksControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @sender = create(:user)
    @bug = create(:app_feedback, kind: 'bug', message: 'Crash on save', platform: 'ios', app_version: '1.2.0',
                                 user: @sender, sentry_event_id: 'evt123', diagnostics: { 'audio' => { 'ladder' => 'ok-ladder' } })
    @bug.screenshot.attach(fixture_upload('avatar.png', 'image/png'))
    @idea = create(:app_feedback, kind: 'idea', message: 'More drum kits', platform: 'android', app_version: '1.1.0')
    @rating = create(:app_feedback, kind: 'rating', rating: 2, message: nil, moment: 'first_play', platform: 'ios',
                                    app_version: '1.2.0')
    @archived = create(:app_feedback, kind: 'other', message: 'Old note', status: 'archived', app_version: '1.0.0')
    @old = create(:app_feedback, kind: 'idea', message: 'Old idea', app_version: '1.0.0')
    @old.update_column(:created_at, Time.zone.parse('2026-01-15 12:00'))
  end

  teardown do
    Warden.test_reset!
    AppFeedback.reset_config!
  end

  def sign_in(user)
    login_as(user, scope: :spree_user)
  end

  def listed
    response.body.scan(/id="app_feedback_(\d+)"/).flatten.map(&:to_i).sort
  end

  test 'admin only' do
    get '/admin/feedback'
    refute_includes response.body, "app_feedback_#{@bug.id}", 'anonymous gets the login page'

    sign_in(create(:user))
    get '/admin/feedback'
    refute_includes response.body, "app_feedback_#{@bug.id}"
    get "/admin/feedback/#{@bug.id}"
    refute_includes response.body, 'Crash on save'
    patch "/admin/feedback/#{@bug.id}", params: { app_feedback: { status: 'done' } }
    post '/admin/feedback/bulk_archive', params: { ids: [@bug.id] }
    assert_equal 'new', @bug.reload.status
  end

  test 'the sidebar has a Feedback tab for admins' do
    sign_in(@admin)
    get '/admin/feedback'
    assert_response :success
    assert_includes response.body, 'sidebarAppFeedback'
  end

  test 'index lists everything but archived, newest first' do
    sign_in(@admin)
    get '/admin/feedback'
    assert_response :success
    assert_equal [@bug.id, @idea.id, @rating.id, @old.id].sort, listed
    assert_includes response.body, 'Crash on save'
    assert_operator response.body.index("app_feedback_#{@rating.id}"), :<, response.body.index("app_feedback_#{@old.id}")
    assert_includes response.body, 'feedback-has-screenshot'
    assert_includes response.body, '2 of 5'
  end

  test 'index filters' do
    sign_in(@admin)
    get '/admin/feedback', params: { kind: 'idea' }
    assert_equal [@idea.id, @old.id].sort, listed

    get '/admin/feedback', params: { rating: '2' }
    assert_equal [@rating.id], listed

    get '/admin/feedback', params: { platform: 'android' }
    assert_equal [@idea.id], listed

    get '/admin/feedback', params: { app_version: '1.2.0' }
    assert_equal [@bug.id, @rating.id].sort, listed

    get '/admin/feedback', params: { status: 'archived' }
    assert_equal [@archived.id], listed

    get '/admin/feedback', params: { status: 'all' }
    assert_equal 5, listed.size

    get '/admin/feedback', params: { screenshot: 'yes' }
    assert_equal [@bug.id], listed

    get '/admin/feedback', params: { screenshot: 'no' }
    assert_equal [@idea.id, @rating.id, @old.id].sort, listed

    get '/admin/feedback', params: { from: '2026-01-01', to: '2026-01-31' }
    assert_equal [@old.id], listed

    get '/admin/feedback', params: { from: 'garbage', kind: 'nonsense', rating: '9' }
    assert_response :success
    assert_equal 4, listed.size
  end

  test 'index paginates' do
    sign_in(@admin)
    create_list(:app_feedback, Spree::Admin::AppFeedbacksController::PER_PAGE, kind: 'idea')
    get '/admin/feedback'
    assert_equal Spree::Admin::AppFeedbacksController::PER_PAGE, listed.size
    get '/admin/feedback', params: { page: 2 }
    assert_equal 4, listed.size
  end

  test 'show has the message, screenshot, diagnostics, sender and Sentry link' do
    AppFeedback.config.sentry_url_template = 'https://sentry.example.com/issues/?query=%{id}'
    sign_in(@admin)
    get "/admin/feedback/#{@bug.id}"
    assert_response :success
    body = response.body
    assert_includes body, 'Crash on save'
    assert_includes body, 'feedback_screenshot'
    assert_includes body, 'ok-ladder'
    assert_includes body, @sender.email
    assert_includes body, "/admin/users/#{@sender.id}/edit"
    assert_includes body, 'https://sentry.example.com/issues/?query=evt123'
  end

  test 'show hides the Sentry link without a template' do
    AppFeedback.config.sentry_url_template = nil
    sign_in(@admin)
    get "/admin/feedback/#{@idea.id}"
    assert_response :success
    refute_includes response.body, 'open_in_sentry'
    assert_includes response.body, 'Not signed in'
  end

  test 'update sets status and admin note' do
    sign_in(@admin)
    patch "/admin/feedback/#{@bug.id}", params: { app_feedback: { status: 'triaged', admin_note: '  repro on iOS 18  ' } }
    assert_redirected_to "/admin/feedback/#{@bug.id}"
    @bug.reload
    assert_equal 'triaged', @bug.status
    assert_equal 'repro on iOS 18', @bug.admin_note

    patch "/admin/feedback/#{@bug.id}", params: { app_feedback: { status: 'bogus' } }
    assert_equal 'triaged', @bug.reload.status
  end

  test 'bulk archive' do
    sign_in(@admin)
    post '/admin/feedback/bulk_archive', params: { ids: [@bug.id, @idea.id] }
    assert_response :redirect
    assert_equal 'archived', @bug.reload.status
    assert_equal 'archived', @idea.reload.status
    assert_equal 'new', @rating.reload.status
  end
end
