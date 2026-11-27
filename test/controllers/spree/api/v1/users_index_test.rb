require 'test_helper'

# dna-admin replaces Spree's API v1 UsersController; admin apps (Spree Admin Native's Customers
# tab) still list and read users through Spree's index and show.
class Spree::Api::V1::UsersIndexTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, email: 'admin@example.com')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @admin.generate_spree_api_key!
    @maya = create(:user, email: 'maya@example.com')
    @sam = create(:user, email: 'sam@example.com')
  end

  def get_json(path, params = {}, key = @admin.spree_api_key)
    get path, params: params, headers: { 'X-Spree-Token' => key }
    JSON.parse(response.body)
  end

  test 'an admin lists users with emails, paged' do
    body = get_json('/api/v1/users.json', { per_page: 2 })
    assert_equal 200, response.status, response.body
    assert_equal 2, body['users'].size
    assert body['users'].all? { |u| u['email'].present? }
    assert_operator body['pages'], :>=, 2
    refute_includes response.headers['Cache-Control'].to_s, 'public'
  end

  test 'an admin searches by email start' do
    body = get_json('/api/v1/users.json', { q: { email_start: 'maya' } })
    assert_equal ['maya@example.com'], body['users'].map { |u| u['email'] }
  end

  test 'an admin reads one user' do
    body = get_json("/api/v1/users/#{@maya.id}.json")
    assert_equal 200, response.status
    assert_equal 'maya@example.com', body['email']
    assert_equal @maya.id, body['id']
  end

  test 'a customer only sees themselves' do
    @maya.generate_spree_api_key!
    body = get_json('/api/v1/users.json', {}, @maya.spree_api_key)
    assert_equal ['maya@example.com'], body['users'].map { |u| u['email'] }
    get "/api/v1/users/#{@sam.id}.json", headers: { 'X-Spree-Token' => @maya.spree_api_key }
    assert_equal 404, response.status
  end

  test 'listing users needs an api key' do
    get '/api/v1/users.json'
    assert_equal 401, response.status
  end
end
