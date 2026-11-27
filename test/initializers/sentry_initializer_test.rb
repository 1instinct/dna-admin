require 'test_helper'

# config/initializers/sentry.rb: off without SENTRY_DSN, and Spree credentials never leave.
class SentryInitializerTest < ActiveSupport::TestCase
  Request = Struct.new(:headers, :url, :query_string)
  Event = Struct.new(:request)
  Crumb = Struct.new(:data)

  setup do
    @dsn = ENV['SENTRY_DSN']
    ENV['SENTRY_DSN'] = 'http://public@127.0.0.1:9/1'
    load Rails.root.join('config/initializers/sentry.rb')
  end

  teardown do
    @dsn ? ENV['SENTRY_DSN'] = @dsn : ENV.delete('SENTRY_DSN')
    Sentry.close if Sentry.respond_to?(:close)
  end

  test 'starts with no PII and excludes routine 404s' do
    assert Sentry.initialized?
    refute Sentry.configuration.send_default_pii
    assert_includes Sentry.configuration.excluded_exceptions, 'ActiveRecord::RecordNotFound'
  end

  test 'filters Spree token headers and token query parameters' do
    request = Request.new(
      { 'X-Spree-Token' => 'key', 'X-Spree-Order-Token' => 'guest', 'Accept' => 'application/json' },
      'https://admin.example.com/api/v1/orders?token=abc&page=2',
      'token=abc&page=2'
    )
    event = Sentry.configuration.before_send.call(Event.new(request), {})
    assert_equal '[Filtered]', event.request.headers['X-Spree-Token']
    assert_equal '[Filtered]', event.request.headers['X-Spree-Order-Token']
    assert_equal 'application/json', event.request.headers['Accept']
    assert_equal 'https://admin.example.com/api/v1/orders?token=[Filtered]&page=2', event.request.url
    assert_equal 'token=[Filtered]&page=2', event.request.query_string
  end

  test 'filters tokens in breadcrumb URLs' do
    crumb = Sentry.configuration.before_breadcrumb.call(Crumb.new({ url: 'https://pay.example.com/cb?code=123&x=1' }), {})
    assert_equal 'https://pay.example.com/cb?code=[Filtered]&x=1', crumb.data[:url]
  end
end
