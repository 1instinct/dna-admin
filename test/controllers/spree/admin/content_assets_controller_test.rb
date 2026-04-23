require 'test_helper'

class Spree::Admin::ContentAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:spree_user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @admin.generate_spree_api_key!
    @asset = create(:content_asset, tag: "homepage", alt_text: "Test image")
  end

  test "GET index renders successfully" do
    get admin_content_assets_path, headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_response :ok
  end

  test "GET new renders upload form" do
    get new_admin_content_asset_path, headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_response :ok
  end

  test "POST create with valid file creates asset" do
    file = fixture_file_upload("test/fixtures/files/test-image.png", "image/png")
    assert_difference "ContentAsset.count", 1 do
      post admin_content_assets_path,
        params: { content_asset: { alt_text: "New", tag: "test", file: file } },
        headers: { "X-Spree-Token" => @admin.spree_api_key }
    end
    assert_redirected_to admin_content_assets_path
  end

  test "GET edit renders edit form" do
    get edit_admin_content_asset_path(@asset),
      headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_response :ok
  end

  test "PUT update changes metadata" do
    put admin_content_asset_path(@asset),
      params: { content_asset: { alt_text: "Updated" } },
      headers: { "X-Spree-Token" => @admin.spree_api_key }
    assert_redirected_to admin_content_assets_path
    assert_equal "Updated", @asset.reload.alt_text
  end

  test "DELETE destroy removes asset" do
    assert_difference "ContentAsset.count", -1 do
      delete admin_content_asset_path(@asset),
        headers: { "X-Spree-Token" => @admin.spree_api_key }
    end
    assert_redirected_to admin_content_assets_path
  end
end
