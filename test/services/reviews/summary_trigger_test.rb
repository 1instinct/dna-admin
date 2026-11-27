require 'test_helper'
require 'rake'
require 'minitest/mock'

# M7 trigger: Reviews::SummaryTrigger, and `rake reviews:dispatch` calling it once per run.
class Reviews::SummaryTriggerTest < ActiveSupport::TestCase
  URL = 'https://shop.example.com/api/internal/reviews/summarize'.freeze
  ENVS = { 'SITE_URL' => 'https://shop.example.com/', 'INTERNAL_CRON_SECRET' => 'cron-secret' }.freeze

  setup do
    @log = StringIO.new
    @logger = ActiveSupport::Logger.new(@log)
  end

  test 'POSTs to the storefront with the shared secret' do
    stub = stub_request(:post, URL).with(headers: { 'Authorization' => 'Bearer cron-secret' }).
           to_return(status: 200, body: '{"processed":3,"failed":0,"skipped":0}')
    assert_equal :ok, Reviews::SummaryTrigger.call(env: ENVS, logger: @logger)
    assert_requested stub, times: 1
    assert_match(/processed/, @log.string)
  end

  test 'not configured without both SITE_URL and INTERNAL_CRON_SECRET' do
    assert_equal :not_configured, Reviews::SummaryTrigger.call(env: ENVS.merge('INTERNAL_CRON_SECRET' => ' '), logger: @logger)
    assert_equal :not_configured, Reviews::SummaryTrigger.call(env: ENVS.except('SITE_URL'), logger: @logger)
    refute Reviews::SummaryTrigger.configured?({})
    assert Reviews::SummaryTrigger.configured?(ENVS)
    assert_not_requested :post, URL
  end

  test 'failures are logged and never raised' do
    stub_request(:post, URL).to_return(status: 401, body: '{"error":"unauthorized"}')
    assert_equal :failed, Reviews::SummaryTrigger.call(env: ENVS, logger: @logger)
    assert_match(/HTTP 401/, @log.string)

    stub_request(:post, URL).to_timeout
    assert_equal :error, Reviews::SummaryTrigger.call(env: ENVS, logger: @logger)
    stub_request(:post, URL).to_raise(Errno::ECONNREFUSED)
    assert_equal :error, Reviews::SummaryTrigger.call(env: ENVS, logger: @logger)
    assert_equal :error, Reviews::SummaryTrigger.call(env: ENVS.merge('SITE_URL' => 'shop.example.com'), logger: @logger)
    assert_match(/AI summary refresh error/, @log.string)
  end

  test 'timeouts: 5 s to connect, 300 s to read' do
    assert_equal [5, 300], [Reviews::SummaryTrigger::OPEN_TIMEOUT, Reviews::SummaryTrigger::READ_TIMEOUT]
    seen = nil
    start = lambda do |_host, _port, **options, &block|
      seen = options
      block.call(Struct.new(:request).new(Net::HTTPOK.new('1.1', '200', 'OK')))
    end
    Net::HTTP.stub(:start, start) { Reviews::SummaryTrigger.call(env: ENVS, logger: @logger) }
    assert_equal({ use_ssl: true, open_timeout: 5, read_timeout: 300 }, seen)
  end

  test 'call_in_background runs the same call on a thread' do
    stub = stub_request(:post, URL).to_return(status: 200, body: '{}')
    thread = Reviews::SummaryTrigger.call_in_background(env: ENVS, logger: @logger)
    assert_equal :ok, thread.value
    assert_requested stub
  end
end

class Reviews::SummaryTriggerDispatchTest < ActiveSupport::TestCase
  URL = Reviews::SummaryTriggerTest::URL
  ENVS = Reviews::SummaryTriggerTest::ENVS

  setup { reviews_enable!(ai_summary_enabled: true) }

  test 'dispatch calls it once when AI summaries are on and both envs are set' do
    stub = stub_request(:post, URL).to_return(status: 200, body: '{}')
    with_env(ENVS) do
      dispatch = ReviewRequests::Dispatch.new
      dispatch.call
      assert_equal :ok, dispatch.summary_trigger
    end
    assert_requested stub, times: 1
  end

  test 'dispatch skips it when AI summaries are off or an env is missing' do
    Spree::ReviewSetting.current.update!(ai_summary_enabled: false)
    with_env(ENVS) { ReviewRequests::Dispatch.call }

    Spree::ReviewSetting.current.update!(ai_summary_enabled: true)
    with_env(ENVS.merge('INTERNAL_CRON_SECRET' => nil)) do
      dispatch = ReviewRequests::Dispatch.new
      dispatch.call
      assert_nil dispatch.summary_trigger
    end
    with_env(ENVS.merge('SITE_URL' => nil)) { ReviewRequests::Dispatch.call }
    assert_not_requested :post, URL
  end

  test 'a failing storefront never fails the dispatch or the rake task' do
    stub_request(:post, URL).to_raise(Errno::ECONNREFUSED)
    with_env(ENVS) do
      counts = ReviewRequests::Dispatch.call
      assert_equal 0, counts[:failed]

      Rails.application.load_tasks unless Rake::Task.task_defined?('reviews:dispatch')
      Rake::Task['reviews:dispatch'].reenable
      out, = capture_io { Rake::Task['reviews:dispatch'].invoke }
      assert_match(/reviews:dispatch sent=0 .* ai_summaries=error/, out)
    end
  end
end
