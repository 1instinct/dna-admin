require 'test_helper'
require 'minitest/mock'

# Parsing of the iTunes lookup response; the HTTP call itself is stubbed (no network in tests).
class AppStoreLookupTest < ActiveSupport::TestCase
  test 'returns the live version' do
    AppStoreLookup.stub(:fetch, { resultCount: 1, results: [{ version: '2.6.0' }] }.to_json) do
      assert_equal '2.6.0', AppStoreLookup.live_version('com.example.app')
    end
  end

  test 'returns nil when the store has no such app' do
    AppStoreLookup.stub(:fetch, { resultCount: 0, results: [] }.to_json) do
      assert_nil AppStoreLookup.live_version('com.example.app')
    end
  end

  test 'raises Error on an unreadable response' do
    AppStoreLookup.stub(:fetch, '<html>oops</html>') do
      assert_raises(AppStoreLookup::Error) { AppStoreLookup.live_version('com.example.app') }
    end
  end

  test 'wraps network failures in Error' do
    Net::HTTP.stub(:start, ->(*) { raise Net::OpenTimeout }) do
      error = assert_raises(AppStoreLookup::Error) { AppStoreLookup.live_version('com.example.app') }
      assert_equal 'Net::OpenTimeout', error.message
    end
  end

  test 'treats a non-2xx response as a failure' do
    response = Net::HTTPServiceUnavailable.new('1.1', '503', 'Service Unavailable')
    Net::HTTP.stub(:start, ->(*) { response }) do
      error = assert_raises(AppStoreLookup::Error) { AppStoreLookup.live_version('com.example.app') }
      assert_equal 'HTTP 503', error.message
    end
  end
end
