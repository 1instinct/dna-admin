require 'test_helper'

# Review reports in the admin Reports tab: listed, shown with the review snapshot, hidden or restored.
class Spree::Admin::ContentReportsReviewsTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    reviews_enable!
    @admin = media_admin
    @product = media_product(name: 'Wrap Top')
    author = create(:user)
    reviews_order(@product, user: author)
    @review = reviews_submit(@product, user: author, rating: 1, title: 'Bad', body: 'Fell apart').review
    @reports = Array.new(3) do
      report = Spree::ContentReport.for_review(@review, reporter: create(:user), reason: 'other')
      report.save!
      report
    end
    Reviews::Reports.after_report(@review)
    login_as(@admin, scope: :spree_user)
  end

  teardown { Warden.test_reset! }

  test 'listed and shown with the review as it was reported' do
    get '/admin/content_reports'
    assert_response :success
    assert_includes response.body, "review ##{@review.id} (1★, Wrap Top)"

    get "/admin/content_reports/#{@reports.first.id}"
    assert_response :success
    assert_includes response.body, 'Review at report time'
    assert_includes response.body, 'Fell apart'
    assert_includes response.body, 'Restore review'
    refute_includes response.body, 'Lock account'
  end

  test 'restore puts the review back and closes its other open reports' do
    assert_equal 'pending', @review.reload.status
    post "/admin/content_reports/#{@reports.first.id}/restore_review"
    assert_equal 'published', @review.reload.status
    assert_equal 0, @review.reports_count
    assert_equal %w[actioned dismissed dismissed], @reports.map { |report| report.reload.status }
    assert_equal 1, @product.reload.reviews_count
  end

  test 'hide takes it off the site' do
    post "/admin/content_reports/#{@reports.first.id}/hide_review"
    assert_equal 'hidden', @review.reload.status
    assert_equal 2, @review.reports_count
  end
end
