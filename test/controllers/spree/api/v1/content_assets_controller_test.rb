require 'test_helper'

class Spree::Api::V1::ContentAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:spree_user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @admin.generate_spree_api_key!
    @asset = create(:content_asset, tag: "homepage", alt_text: "Hero banner")
  end

  # --- Public endpoints (no auth) ---

  test "GET index returns list of content assets" do
    get "/api/v1/content_assets"
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 200, json["response_code"]
    assert json["response_data"]["content_assets"].is_a?(Array)
    assert json["response_data"]["total_records"] >= 1
  end

  test "GET index filters by tag" do
    create(:content_asset, tag: "footer")
    get "/api/v1/content_assets?tag=homepage"
    json = JSON.parse(response.body)
    assets = json["response_data"]["content_assets"]
    assert assets.all? { |a| a["tag"] == "homepage" }
  end

  test "GET index supports search" do
    get "/api/v1/content_assets?search=hero"
    json = JSON.parse(response.body)
    assets = json["response_data"]["content_assets"]
    assert assets.any? { |a| a["alt_text"].downcase.include?("hero") }
  end

  test "GET index supports pagination" do
    5.times { create(:content_asset) }
    get "/api/v1/content_assets?limit=2&offset=0"
    json = JSON.parse(response.body)
    assert json["response_data"]["content_assets"].length <= 2
  end

  test "GET show returns single asset with all variant URLs" do
    get "/api/v1/content_assets/#{@asset.id}"
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 200, json["response_code"]
    data = json["response_data"]
    assert_equal @asset.id, data["id"]
    assert data["urls"].key?("original")
    assert data["urls"].key?("small")
    assert data["urls"].key?("widescreen")
  end

  test "GET show returns 400 for missing asset" do
    get "/api/v1/content_assets/99999"
    json = JSON.parse(response.body)
    assert_equal 400, json["response_code"]
  end

  # --- Admin-only endpoints ---

  test "POST create requires authentication" do
    file = fixture_file_upload("test/fixtures/files/test-image.png", "image/png")
    post "/api/v1/content_assets", params: { file: file, alt_text: "New" }
    assert_response :unauthorized
  end

  test "POST create uploads asset with admin auth" do
    file = fixture_file_upload("test/fixtures/files/test-image.png", "image/png")
    post "/api/v1/content_assets",
      params: { file: file, alt_text: "New image", tag: "hero" },
      headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "New image", json["response_data"]["alt_text"]
  end

  test "PUT update changes metadata" do
    put "/api/v1/content_assets/#{@asset.id}",
      params: { alt_text: "Updated alt", tag: "updated" },
      headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_response :ok
    @asset.reload
    assert_equal "Updated alt", @asset.alt_text
    assert_equal "updated", @asset.tag
  end

  test "DELETE destroy removes asset" do
    assert_difference "ContentAsset.count", -1 do
      delete "/api/v1/content_assets/#{@asset.id}",
        headers: { "X-Spree-Token" => @admin.spree_api_key }
    end
    assert_response :ok
  end

  test "DELETE destroy requires authentication" do
    delete "/api/v1/content_assets/#{@asset.id}"
    assert_response :unauthorized
  end
end
