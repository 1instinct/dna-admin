require 'test_helper'

class AppFeedbackTest < ActiveSupport::TestCase
  teardown { AppFeedback.reset_config! }

  test 'a valid anonymous bug report, new by default' do
    feedback = build(:app_feedback)
    assert feedback.valid?, feedback.errors.full_messages.to_sentence
    assert_equal 'new', feedback.status
  end

  test 'kind and status come from fixed lists' do
    refute build(:app_feedback, kind: 'rant').valid?
    refute build(:app_feedback, kind: nil).valid?
    refute build(:app_feedback, status: 'closed').valid?
    AppFeedback::KINDS.each do |kind|
      assert build(:app_feedback, kind: kind, rating: 3).valid?, kind
    end
  end

  test 'message is required unless kind is rating, and at most 2000 characters' do
    refute build(:app_feedback, message: '').valid?
    assert build(:app_feedback, kind: 'rating', rating: 4, message: nil).valid?
    assert build(:app_feedback, message: 'm' * 2000).valid?
    feedback = build(:app_feedback, message: 'm' * 2001)
    refute feedback.valid?
    assert feedback.errors[:message].any?
  end

  test 'rating is 1 to 5, a whole number, and required for kind rating' do
    refute build(:app_feedback, kind: 'rating', rating: nil).valid?
    [0, 6, -1].each { |r| refute build(:app_feedback, kind: 'rating', rating: r).valid?, r.to_s }
    refute build(:app_feedback, kind: 'rating', rating: '4.5').valid?
    (1..5).each { |r| assert build(:app_feedback, kind: 'rating', rating: r).valid?, r.to_s }
    assert build(:app_feedback, kind: 'idea', rating: nil).valid?
  end

  test 'install_id is required when there is no user' do
    refute build(:app_feedback, install_id: nil).valid?
    assert build(:app_feedback, install_id: nil, user: create(:user)).valid?
  end

  test 'email is optional and validated' do
    assert build(:app_feedback, email: nil).valid?
    assert build(:app_feedback, email: 'tester@example.com').valid?
    refute build(:app_feedback, email: 'not an email').valid?
  end

  test 'short fields are capped and null bytes refused' do
    refute build(:app_feedback, device_model: 'x' * 129).valid?
    refute build(:app_feedback, message: "a\u0000b").valid?
  end

  test 'diagnostics must be a JSON object of at most 64 KB' do
    assert build(:app_feedback, diagnostics: { 'audio' => { 'rate' => 48_000 } }).valid?
    refute build(:app_feedback, diagnostics: [1, 2]).valid?
    refute build(:app_feedback, diagnostics: { 'x' => "a\u0000" }).valid?

    filler = 'd' * (64.kilobytes - JSON.generate('pad' => '').bytesize)
    at_limit = build(:app_feedback, diagnostics: { 'pad' => filler })
    assert_equal 64.kilobytes, at_limit.diagnostics_bytes
    assert at_limit.valid?
    over = build(:app_feedback, diagnostics: { 'pad' => "#{filler}d" })
    refute over.valid?
    assert over.errors[:diagnostics].any?
  end

  test 'screenshot must be a JPEG or PNG of at most 5 MB' do
    feedback = build(:app_feedback)
    feedback.screenshot.attach(fixture_upload('avatar.png', 'image/png'))
    assert feedback.valid?

    gif = build(:app_feedback)
    gif.screenshot.attach(fixture_upload('avatar.gif', 'image/gif'))
    refute gif.valid?
    assert gif.errors[:screenshot].any?

    big = build(:app_feedback)
    big.screenshot.attach(io: StringIO.new("\xFF\xD8\xFF".b + ('0' * (5.megabytes + 1))), filename: 'big.jpg', content_type: 'image/jpeg')
    refute big.valid?
    assert big.errors[:screenshot].any?
  end

  test 'sentry_url fills the template and needs both parts' do
    feedback = build(:app_feedback, sentry_event_id: 'abc 123')
    AppFeedback.config.sentry_url_template = nil
    assert_nil feedback.sentry_url
    AppFeedback.config.sentry_url_template = 'https://sentry.example.com/issues/?query=%{id}'
    assert_equal 'https://sentry.example.com/issues/?query=abc%20123', feedback.sentry_url
    AppFeedback.config.sentry_url_template = 'javascript:alert(%{id})'
    assert_nil feedback.sentry_url
    AppFeedback.config.sentry_url_template = 'https://sentry.example.com/?q=%{id}'
    assert_nil build(:app_feedback, sentry_event_id: nil).sentry_url
  end

  test 'a deleted user leaves the feedback unlinked' do
    user = create(:user)
    feedback = create(:app_feedback, user: user)
    Spree::User.where(id: user.id).delete_all
    assert_nil feedback.reload.user_id
  end
end
