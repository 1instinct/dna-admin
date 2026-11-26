require 'test_helper'

# Reviews > Review settings: the singleton Spree::ReviewSetting form. Admins only.
class Spree::Admin::ReviewSettingsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = media_admin
    @settings = Spree::ReviewSetting.current
  end

  teardown { Warden.test_reset! }

  test 'admin only' do
    get '/admin/review_settings/edit'
    refute_includes response.body, 'review_settings_form', 'anonymous gets the login page'

    login_as(create(:user), scope: :spree_user)
    get '/admin/review_settings/edit'
    assert_response :redirect
    patch '/admin/review_settings', params: { review_setting: { enabled: '1', points_per_review: 999 } }
    @settings.reload
    refute @settings.enabled
    assert_equal 50, @settings.points_per_review
  end

  test 'the index URL goes to the form, which explains the rating never matters' do
    login_as(@admin, scope: :spree_user)
    get '/admin/review_settings'
    assert_redirected_to '/admin/review_settings/edit'
    follow_redirect!
    assert_response :success
    assert_select '#review_settings_compliance', /never changes what happens to a review/
    assert_select '#review_settings_compliance', /16 CFR 465/
    %w[enabled store_reviews_enabled questions_enabled auto_publish photos_require_approval ai_summary_enabled].each do |field|
      assert_select "input[type=checkbox][name='review_setting[#{field}]']"
    end
    %w[request_delay_days international_request_delay_days reminder_delay_days request_expiry_days
       points_per_review points_photo_bonus ai_summary_min_reviews].each do |field|
      assert_select "input[type=number][name='review_setting[#{field}]']"
    end
    assert_select 'input[name="review_setting[request_delay_days]"][value="7"]'
  end

  test 'the sidebar has the Review questions and Review settings tabs' do
    login_as(@admin, scope: :spree_user)
    get '/admin/review_settings/edit'
    assert_select '#sidebar_review_settings.selected a[href="/admin/review_settings/edit"]', /Review settings/
    assert_select '#sidebar_review_questions a[href="/admin/review_questions"]', /Review questions/
  end

  test 'update saves every field' do
    login_as(@admin, scope: :spree_user)
    patch '/admin/review_settings', params: { review_setting: {
      enabled: '1', store_reviews_enabled: '1', questions_enabled: '1', auto_publish: '0', photos_require_approval: '0',
      request_delay_days: '5', international_request_delay_days: '12', reminder_delay_days: '4', request_expiry_days: '30',
      points_per_review: '25', points_photo_bonus: '10', ai_summary_enabled: '1', ai_summary_min_reviews: '8'
    } }
    assert_redirected_to '/admin/review_settings/edit'
    assert_equal 'Review settings saved.', flash[:success]
    s = Spree::ReviewSetting.current
    assert_equal [true, true, true, false, false], [s.enabled, s.store_reviews_enabled, s.questions_enabled, s.auto_publish, s.photos_require_approval]
    assert_equal [5, 12, 4, 30], [s.request_delay_days, s.international_request_delay_days, s.reminder_delay_days, s.request_expiry_days]
    assert_equal [25, 10, true, 8], [s.points_per_review, s.points_photo_bonus, s.ai_summary_enabled, s.ai_summary_min_reviews]
    assert_equal 1, Spree::ReviewSetting.count
  end

  test 'invalid values re-render the form with errors and save nothing' do
    login_as(@admin, scope: :spree_user)
    patch '/admin/review_settings', params: { review_setting: { enabled: '1', request_delay_days: '-1', ai_summary_min_reviews: '0' } }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', /Request delay days/
    assert_select '#errorExplanation', /Ai summary min reviews/
    assert_select '#review_settings_form'
    @settings.reload
    refute @settings.enabled
    assert_equal 7, @settings.request_delay_days
  end
end
