require "test_helper"

class Api::V1::PrescriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:spree_user)
    @user.generate_spree_api_key!
    @patient_mapping = create(:patient_mapping, spree_user: @user)
    @prescription = create(:prescription,
      patient_mapping: @patient_mapping,
      drug_name: "Finasteride 1mg",
      status: :pending,
      received_at: 3.days.ago,
      refills_left: 5
    )
    @token = @user.spree_api_key
  end

  test "returns prescriptions for authenticated user" do
    get "/api/v1/prescriptions",
      headers: { "X-Spree-Token" => @token }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["prescriptions"].length
    assert_equal "Finasteride 1mg", json["prescriptions"][0]["drug_name"]
    assert_equal "pending", json["prescriptions"][0]["status"]
  end

  test "returns empty array when no prescriptions" do
    other_user = create(:spree_user)
    other_user.generate_spree_api_key!

    get "/api/v1/prescriptions",
      headers: { "X-Spree-Token" => other_user.spree_api_key }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["prescriptions"].length
  end

  test "returns 401 without authentication" do
    get "/api/v1/prescriptions"

    assert_response :unauthorized
  end

  test "returns single prescription detail" do
    get "/api/v1/prescriptions/#{@prescription.id}",
      headers: { "X-Spree-Token" => @token }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "Finasteride 1mg", json["prescription"]["drug_name"]
    assert_equal "pending", json["prescription"]["status"]
    assert_equal 5, json["prescription"]["refills_left"]
  end

  test "returns 404 for other user prescription" do
    other_user = create(:spree_user)
    other_user.generate_spree_api_key!

    get "/api/v1/prescriptions/#{@prescription.id}",
      headers: { "X-Spree-Token" => other_user.spree_api_key }

    assert_response :not_found
  end
end
