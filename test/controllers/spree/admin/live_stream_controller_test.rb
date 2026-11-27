require 'test_helper'
require 'minitest/mock'

# Mux credentials come from the environment, never from the code.
class Spree::Admin::LiveStreamControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Spree::Core::Engine.routes.url_helpers

  FakeRequest = Struct.new(:result) do
    def execute
      result
    end
  end

  setup do
    @admin = Spree.user_class.create!(email: "mux-admin-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    sign_in @admin, scope: :spree_user
    @saved = ENV.to_h.slice('MUX_TOKEN_ID', 'MUX_TOKEN_SECRET')
  end

  teardown do
    %w[MUX_TOKEN_ID MUX_TOKEN_SECRET].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) }
  end

  test 'the controller holds no literal Mux credentials' do
    source = File.read(Rails.root.join('app/controllers/spree/admin/live_stream_controller.rb'))
    refute_match(/(user|password):\s*['"]/, source)
  end

  test 'without a Mux token, creating a stream says so and calls nothing' do
    ENV.delete('MUX_TOKEN_ID')
    ENV.delete('MUX_TOKEN_SECRET')
    called = false
    RestClient::Request.stub(:new, ->(*) { called = true }) do
      post admin_live_stream_index_path, params: { live_stream: { title: 'Launch' } }
    end
    refute called
    assert_redirected_to admin_live_stream_index_path
    assert_match(/MUX_TOKEN_ID/, flash[:error])
  end

  test 'with a Mux token, requests authenticate with it' do
    ENV['MUX_TOKEN_ID'] = 'test-id'
    ENV['MUX_TOKEN_SECRET'] = 'test-secret'
    seen = nil
    fake = FakeRequest.new([:error, { 'error' => { 'messages' => ['refused'] } }])
    RestClient::Request.stub(:new, ->(opts) { seen = opts; fake }) do
      post admin_live_stream_index_path, params: { live_stream: { title: 'Launch' } }
    end
    assert_equal %w[test-id test-secret], [seen[:user], seen[:password]]
    assert_redirected_to new_admin_live_stream_path
  end
end
