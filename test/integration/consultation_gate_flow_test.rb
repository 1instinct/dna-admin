require "test_helper"

class ConsultationGateFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:spree_user)
    @user.generate_spree_api_key!
    @headers = { "X-Spree-Token" => @user.spree_api_key }
  end

  test "consultation API returns status for authenticated user" do
    get "/api/v1/consultation", headers: @headers
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "none", json["consultation_status"]
    assert_not json["consultation_passed"]
  end

  test "consultation API returns pass after status update" do
    @user.update!(consultation_status: :pass, consultation_completed_at: Time.current)
    get "/api/v1/consultation", headers: @headers
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "pass", json["consultation_status"]
    assert json["consultation_passed"]
  end

  test "consultation API returns 401 without auth" do
    get "/api/v1/consultation"
    assert_response :unauthorized
  end
end
