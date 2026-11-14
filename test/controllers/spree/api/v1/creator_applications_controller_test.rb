require 'test_helper'

# GET/POST/DELETE /api/v1/creator_application
class Spree::Api::V1::CreatorApplicationsControllerTest < ActionDispatch::IntegrationTest
  PATH = '/api/v1/creator_application'.freeze

  setup do
    @user = create(:user)
    @headers = auth(@user)
  end

  def apply_params(extra = {})
    { display_name: 'Night Shift', kinds: %w[pack], about: 'Drums.',
      portfolio_links: [{ label: 'Site', url: 'https://example.com' }] }.merge(extra)
  end

  test 'all endpoints 401 without bearer' do
    get PATH
    assert_response :unauthorized
    post PATH, params: apply_params
    assert_response :unauthorized
    delete PATH
    assert_response :unauthorized
  end

  test 'show is 404 before applying' do
    get PATH, headers: @headers
    assert_response :not_found
  end

  test 'create makes a pending application with samples and show returns it' do
    blob = digital_blob(DigitalAssetsTestHelper::WAV_BYTES, 'demo.wav')
    post PATH, headers: @headers, params: apply_params(sample_upload_signed_ids: [blob.signed_id])
    assert_response :created, response.body
    assert_equal 'pending', json['status']
    assert_equal 'Night Shift', json['display_name']
    assert_equal %w[pack], json['kinds']
    assert_equal [{ 'label' => 'Site', 'url' => 'https://example.com' }], json['portfolio_links']
    assert_equal 'demo.wav', json['samples'].first['filename']
    assert json['samples'].first['url'].present?

    get PATH, headers: @headers
    assert_response :success
    assert_equal 'pending', json['status']
    refute json.key?('reviewed_by_id')
  end

  test 'create accepts a JSON body' do
    post PATH, headers: @headers.merge('Content-Type' => 'application/json'), params: apply_params.to_json
    assert_response :created, response.body
    assert_equal 'https://example.com', json['portfolio_links'].first['url']
  end

  test '422 when one is already pending' do
    create(:creator_application, user: @user)
    post PATH, headers: @headers, params: apply_params
    assert_response :unprocessable_entity
  end

  test '422 when already creator' do
    user = creator_user
    post PATH, headers: auth(user), params: apply_params
    assert_response :unprocessable_entity
    assert_equal 'You are already a creator', json['error']
  end

  test '422 with field errors for an invalid application' do
    post PATH, headers: @headers, params: apply_params(display_name: '', sample_upload_signed_ids: %w[a b c d])
    assert_response :unprocessable_entity
    assert json['fields']['display_name']
    assert json['fields']['samples']
  end

  test 'a rejected applicant may apply again; show returns the latest' do
    old = create(:creator_application, user: @user)
    Creators::Approver.reject!(old, admin_user, 'Not yet')
    get PATH, headers: @headers
    assert_equal 'rejected', json['status']
    assert_equal 'Not yet', json['review_note']

    post PATH, headers: @headers, params: apply_params
    assert_response :created
    get PATH, headers: @headers
    assert_equal 'pending', json['status']
  end

  test 'delete withdraws a pending application; 422 when none pending' do
    create(:creator_application, user: @user)
    delete PATH, headers: @headers
    assert_response :success
    assert_equal 'withdrawn', json['status']

    delete PATH, headers: @headers
    assert_response :unprocessable_entity
  end

  test 'delete is 404 without an application' do
    delete PATH, headers: @headers
    assert_response :not_found
  end
end
