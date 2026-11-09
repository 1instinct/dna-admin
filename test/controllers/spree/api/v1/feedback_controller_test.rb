require 'test_helper'

# POST /api/v1/feedback: optional bearer, install_id when anonymous, multipart screenshot.
class Spree::Api::V1::FeedbackControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create(:user, email: 'sender-secret@example.com')
    AppFeedback.config.notify_email = 'feedback@example.com'
    ActionMailer::Base.deliveries.clear
  end

  teardown { AppFeedback.reset_config! }

  def fields(overrides = {})
    {
      kind: 'bug', message: 'Pads stop responding after a phone call', install_id: 'install-abc',
      platform: 'ios', os_version: '18.1', device_model: 'iPhone15,2', app_version: '1.2.0', build_number: '42',
      channel: 'preview', locale: 'en-US', sentry_event_id: 'a' * 32
    }.merge(overrides)
  end

  # opts: headers:, ip:. A positional hash, so Ruby 2.7 doesn't take the fields for keywords.
  def send_feedback(params = fields, opts = {})
    headers = (opts[:headers] || {}).merge('REMOTE_ADDR' => opts[:ip] || '203.0.113.7')
    post '/api/v1/feedback', params: params, headers: headers
  end

  test 'anonymous multipart feedback with a screenshot and diagnostics is stored' do
    send_feedback(fields(screenshot: fixture_upload('avatar.png', 'image/png'),
                         diagnostics: JSON.generate('audio' => { 'sampleRate' => 48_000 })))

    assert_response :created
    feedback = AppFeedback.find(json['id'])
    assert_equal({ 'id' => feedback.id }, json)
    assert_nil feedback.user_id
    assert_equal 'install-abc', feedback.install_id
    assert_equal 'bug', feedback.kind
    assert_equal 'Pads stop responding after a phone call', feedback.message
    assert_equal %w[ios 18.1 iPhone15,2 1.2.0 42 preview en-US],
                 [feedback.platform, feedback.os_version, feedback.device_model, feedback.app_version,
                  feedback.build_number, feedback.channel, feedback.locale]
    assert_equal 'a' * 32, feedback.sentry_event_id
    assert_equal({ 'audio' => { 'sampleRate' => 48_000 } }, feedback.diagnostics)
    assert feedback.screenshot.attached?
    assert_equal 'image/png', feedback.screenshot.blob.content_type
    assert_equal 'new', feedback.status
  end

  test 'JSON bodies work too, with diagnostics as an object' do
    post '/api/v1/feedback', params: fields(kind: 'rating', rating: 4, moment: 'first_save', message: nil,
                                            diagnostics: { 'viz' => { 'fps' => 60 } }), as: :json
    assert_response :created
    feedback = AppFeedback.find(json['id'])
    assert_equal 4, feedback.rating
    assert_equal 'first_save', feedback.moment
    assert_equal 60, feedback.diagnostics.dig('viz', 'fps')
  end

  test 'a valid bearer links the user; install_id is then optional' do
    send_feedback(fields(install_id: nil, kind: 'idea'), headers: auth(@user))
    assert_response :created
    assert_equal @user.id, AppFeedback.find(json['id']).user_id
  end

  test 'an invalid bearer is 401, not anonymous' do
    send_feedback(fields, headers: bearer('nope'))
    assert_response :unauthorized
    assert_equal 'unauthorized', json['error']
    assert_equal 0, AppFeedback.count
  end

  test 'anonymous without install_id is 422 with fields' do
    send_feedback(fields(install_id: nil))
    assert_response :unprocessable_entity
    assert json['error'].present?
    assert json['fields']['install_id'].any?
  end

  test 'validation errors are 422 with fields' do
    send_feedback(fields(kind: 'rant'))
    assert_response :unprocessable_entity
    assert json['fields']['kind'].any?

    send_feedback(fields(message: ''))
    assert_response :unprocessable_entity
    assert json['fields']['message'].any?

    send_feedback(fields(message: 'm' * 2001))
    assert_response :unprocessable_entity

    send_feedback(fields(kind: 'rating', rating: 9))
    assert_response :unprocessable_entity
    assert json['fields']['rating'].any?

    send_feedback(fields(diagnostics: 'not json'))
    assert_response :unprocessable_entity
    assert json['fields']['diagnostics'].any?

    send_feedback(fields(diagnostics: JSON.generate('pad' => 'd' * 64.kilobytes)))
    assert_response :unprocessable_entity
    assert json['fields']['diagnostics'].any?
    assert_equal 0, AppFeedback.count
  end

  test 'kind is case-insensitive' do
    send_feedback(fields(kind: 'Bug'))
    assert_response :created
  end

  test 'screenshot must really be a JPEG or PNG' do
    send_feedback(fields(screenshot: fixture_upload('avatar.gif', 'image/gif')))
    assert_response :unprocessable_entity
    assert json['fields']['screenshot'].any?

    # Declared as a JPEG, but the bytes are not an image.
    send_feedback(fields(screenshot: bytes_upload('just text, not an image', 'image/jpeg', 'shot.jpg')))
    assert_response :unprocessable_entity
    assert json['fields']['screenshot'].any?

    send_feedback(fields(screenshot: 'a string, not a file'))
    assert_response :unprocessable_entity
    assert_equal 0, AppFeedback.count
  end

  test 'a JPEG is accepted' do
    send_feedback(fields(screenshot: fixture_upload('avatar.jpg', 'image/jpeg')))
    assert_response :created
    assert_equal 'image/jpeg', AppFeedback.find(json['id']).screenshot.blob.content_type
  end

  test 'screenshot over 5 MB is 422' do
    send_feedback(fields(screenshot: bytes_upload("\xFF\xD8\xFF\xE0".b + ('0' * 5.megabytes), 'image/jpeg', 'big.jpg')))
    assert_response :unprocessable_entity
    assert json['fields']['screenshot'].any?
    assert_equal 0, AppFeedback.count
  end

  test 'emails FEEDBACK_EMAIL for a bug, inline, without the sender email or diagnostics' do
    assert_no_enqueued_jobs do
      send_feedback(fields(email: 'reply-to-me@example.com', diagnostics: JSON.generate('secret' => 'diag-value')))
    end
    assert_response :created
    mail = ActionMailer::Base.deliveries.last
    assert mail, 'a feedback email is sent'
    assert_equal ['feedback@example.com'], mail.to
    assert_includes mail.subject, "##{json['id']}"
    body = mail.body.encoded
    assert_includes body, 'Pads stop responding after a phone call'
    assert_includes body, "/admin/feedback/#{json['id']}"
    refute_includes body, 'reply-to-me@example.com'
    refute_includes body, 'diag-value'
  end

  # Spree's own mailers fill ActionMailer's default host with the store URL (the storefront in a
  # headless setup), so only the app's routes host is trusted for the admin link.
  def with_hosts(routes:, mailer:)
    old = [Rails.application.routes.default_url_options, ActionMailer::Base.default_url_options]
    Rails.application.routes.default_url_options = routes
    ActionMailer::Base.default_url_options = mailer
    yield
  ensure
    Rails.application.routes.default_url_options, ActionMailer::Base.default_url_options = old
  end

  test 'the email links the admin with an absolute URL from the routes host' do
    with_hosts(routes: { host: 'admin.example.com', protocol: 'https' }, mailer: { host: 'shop.example.com' }) do
      send_feedback(fields)
    end
    assert_response :created
    body = ActionMailer::Base.deliveries.last.body.encoded
    assert_includes body, "admin: https://admin.example.com/admin/feedback/#{json['id']}"
    refute_includes body, 'shop.example.com'
  end

  test 'the email links the admin by path when no routes host is configured' do
    with_hosts(routes: {}, mailer: { host: 'shop.example.com' }) { send_feedback(fields) }
    assert_response :created
    body = ActionMailer::Base.deliveries.last.body.encoded
    assert_match %r{admin: /admin/feedback/#{json['id']}\s*$}, body
  end

  test 'no email for other kinds or when FEEDBACK_EMAIL is unset' do
    send_feedback(fields(kind: 'idea'))
    assert_response :created
    assert_empty ActionMailer::Base.deliveries

    AppFeedback.config.notify_email = nil
    send_feedback(fields)
    assert_response :created
    assert_empty ActionMailer::Base.deliveries
  end

  test 'a mail failure keeps the feedback and answers 201' do
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    AppFeedbackMailer.define_singleton_method(:new_bug) { |_feedback| raise Net::SMTPFatalError, 'smtp down' }

    send_feedback(fields)

    assert_response :created
    assert AppFeedback.exists?(json['id'])
    assert_includes io.string, "feedback #{json['id']} email failed: Net::SMTPFatalError"
  ensure
    Rails.logger = old_logger
    AppFeedbackMailer.singleton_class.send(:remove_method, :new_bug)
  end

  test '429 on the 11th in a day from one install' do
    10.times do |i|
      send_feedback(fields(message: "report #{i}"), ip: "198.51.100.#{i}")
      assert_response :created
    end
    send_feedback(fields, ip: '198.51.100.200')
    assert_response :too_many_requests
    assert json['error'].present?

    send_feedback(fields(install_id: 'another-install'), ip: '198.51.100.201')
    assert_response :created
  end

  test '429 on the 11th in a day from one user, across installs' do
    headers = auth(@user)
    10.times do |i|
      send_feedback(fields(install_id: "install-#{i}"), headers: headers, ip: "198.51.100.#{i}")
      assert_response :created
    end
    send_feedback(fields(install_id: 'fresh'), headers: headers, ip: '198.51.100.200')
    assert_response :too_many_requests
  end

  test '429 on the 31st in a day from one IP, across installs' do
    30.times do |i|
      send_feedback(fields(install_id: "install-#{i}"))
      assert_response :created
    end
    send_feedback(fields(install_id: 'install-new'))
    assert_response :too_many_requests
    send_feedback(fields(install_id: 'install-new'), ip: '203.0.113.8')
    assert_response :created
  end

  test 'a failed screenshot upload still stores the feedback once, notes it, emails and answers 201' do
    service = ActiveStorage::Blob.service
    service.define_singleton_method(:upload) { |*_args, **_opts| raise IOError, 'storage down' }
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      send_feedback(fields(screenshot: fixture_upload('avatar.png', 'image/png')))
    end

    assert_response :created
    assert_equal 1, AppFeedback.count
    feedback = AppFeedback.find(json['id'])
    refute feedback.screenshot.attached?
    assert_includes feedback.admin_note, 'screenshot upload failed'
    assert_includes io.string, "feedback #{feedback.id} screenshot upload failed: IOError"
    assert ActionMailer::Base.deliveries.last, 'the bug email still goes out'
    assert_equal 0, ActiveStorage::Attachment.where(record_type: 'AppFeedback').count
  ensure
    Rails.logger = old_logger
    service.singleton_class.send(:remove_method, :upload)
  end

  test 'the screenshot is uploaded before the row is saved, so it is readable right after 201' do
    send_feedback(fields(screenshot: fixture_upload('avatar.png', 'image/png')))
    assert_response :created
    blob = AppFeedback.find(json['id']).screenshot.blob
    assert blob.service.exist?(blob.key)
    assert_equal File.binread(Rails.root.join('test', 'fixtures', 'files', 'avatar.png')), blob.download
  end

  test 'a request the IP limit refuses does not use up the sender limit, and the other way round' do
    AppFeedback.config.rate_limits = { sender: { limit: 3, window: 24.hours }, ip: { limit: 2, window: 24.hours } }

    2.times do
      send_feedback(fields, ip: '198.51.100.1')
      assert_response :created
    end
    send_feedback(fields, ip: '198.51.100.1')
    assert_response :too_many_requests, 'the IP is over its limit'

    send_feedback(fields, ip: '198.51.100.2')
    assert_response :created, 'the refused request did not count against the install'
    send_feedback(fields, ip: '198.51.100.3')
    assert_response :too_many_requests, 'now the install is over its limit'

    send_feedback(fields(install_id: 'other-install'), ip: '198.51.100.3')
    assert_response :created, 'the install-refused request did not count against the IP'
  end

  test 'the limit resets after a day, refused feedback does not use it, and IPs are not stored' do
    10.times do
      send_feedback(fields(kind: 'rant'))
      assert_response :unprocessable_entity
    end
    10.times { send_feedback(fields) }
    send_feedback(fields)
    assert_response :too_many_requests

    AppFeedback::RateCounter.update_all(window_started_at: 25.hours.ago)
    send_feedback(fields)
    assert_response :created
    refute AppFeedback::RateCounter.where('key LIKE ?', '%203.0.113.7%').exists?
  end
end
