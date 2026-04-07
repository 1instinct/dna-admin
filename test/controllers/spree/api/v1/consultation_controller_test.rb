require "test_helper"

class Spree::Api::V1::ConsultationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:spree_user)
    @user.generate_spree_api_key!
  end

  test "returns consultation status for authenticated user" do
    @user.update!(consultation_status: :pass, consultation_completed_at: 2.days.ago)
    get "/api/v1/consultation", headers: { "X-Spree-Token" => @user.spree_api_key }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "pass", json["consultation_status"]
    assert_not_nil json["consultation_completed_at"]
    assert json["consultation_passed"]
  end

  test "returns none status for user without consultation" do
    get "/api/v1/consultation", headers: { "X-Spree-Token" => @user.spree_api_key }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "none", json["consultation_status"]
    assert_nil json["consultation_completed_at"]
    assert_not json["consultation_passed"]
  end

  test "returns 401 for unauthenticated request" do
    get "/api/v1/consultation"
    assert_response :unauthorized
  end

  test "returns pending status with encounter ID" do
    @user.update!(consultation_status: :pending, mdi_encounter_id: "enc_123")
    get "/api/v1/consultation", headers: { "X-Spree-Token" => @user.spree_api_key }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "pending", json["consultation_status"]
    assert_equal "enc_123", json["mdi_encounter_id"]
  end
end
