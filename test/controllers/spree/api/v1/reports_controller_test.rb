require 'test_helper'

# POST /api/v1/reports { target: { type: "profile", handle }, reason, details }. Bearer.
class Spree::Api::V1::ReportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @reporter = create(:user)
    create(:user_profile, user: @reporter, handle: 'reporter')
    @target_user = create(:user, email: 'target-secret@example.com')
    @target = create(:user_profile, user: @target_user, handle: 'target', name: 'Target', bio: 'spam spam')
    @headers = auth(@reporter)
    Profiles.config.moderation_email = 'moderation@example.com'
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    Profiles.reset_config!
  end

  def report!(handle: 'target', reason: 'spam', details: 'ads', headers: @headers)
    post '/api/v1/reports', params: { target: { type: 'profile', handle: handle }, reason: reason, details: details },
                            headers: headers, as: :json
  end

  test 'requires a bearer' do
    post '/api/v1/reports', params: { target: { type: 'profile', handle: 'target' }, reason: 'spam' }, as: :json
    assert_response :unauthorized
  end

  test 'creates a report with a snapshot and emails the moderation inbox' do
    perform_enqueued_jobs do
      report!
    end
    assert_response :created
    report = Spree::ContentReport.find(json['id'])
    assert_equal({ 'id' => report.id }, json)
    assert_equal @reporter.id, report.reporter_id
    assert_equal @target, report.reportable
    assert_equal 'spam', report.reason
    assert_equal 'ads', report.details
    assert_equal 'open', report.status
    assert_equal 'target', report.snapshot['handle']
    assert_equal 'spam spam', report.snapshot['bio']

    mail = ActionMailer::Base.deliveries.last
    assert mail, 'a moderation email is sent'
    assert_equal ['moderation@example.com'], mail.to
    assert_includes mail.subject, '@target'
    body = mail.body.encoded
    assert_includes body, 'spam spam'
    refute_includes body, 'target-secret@example.com'
  end

  test 'no email when MODERATION_EMAIL is unset, report still stored' do
    Profiles.config.moderation_email = nil
    perform_enqueued_jobs { report! }
    assert_response :created
    assert_empty ActionMailer::Base.deliveries
  end

  test '429 on the 21st report in 24 hours' do
    20.times do
      report!
      assert_response :created
    end
    report!
    assert_response :too_many_requests
    assert json['error'].present?
    assert_equal 20, Spree::ContentReport.count
  end

  test '404 for an unknown handle' do
    report!(handle: 'nobody')
    assert_response :not_found
  end

  test '404 for a hidden profile or one in a block either way' do
    Spree::UserBlock.block!(@target_user, @reporter)
    report!
    assert_response :not_found
    Spree::UserBlock.delete_all
    Spree::UserBlock.block!(@reporter, @target_user)
    report!
    assert_response :not_found
    Spree::UserBlock.delete_all
    @target.update_column(:hidden_at, Time.current)
    report!
    assert_response :not_found
  end

  test 'reporting yourself is 422' do
    report!(handle: 'reporter')
    assert_response :unprocessable_entity
  end

  test 'unknown reason, long details or target type are 422 with fields' do
    report!(reason: 'boring')
    assert_response :unprocessable_entity
    assert json['fields']['reason'].any?

    report!(details: 'd' * 501)
    assert_response :unprocessable_entity
    assert json['fields']['details'].any?

    post '/api/v1/reports', params: { target: { type: 'post', handle: 'target' }, reason: 'spam' }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert json['fields']['target'].any?

    post '/api/v1/reports', params: { reason: 'spam' }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end
end
