require 'test_helper'

# Admin "Videos" tab on a product.
class Spree::Admin::ProductVideosControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @product = media_product(name: 'Admin Video Product')
    @admin = media_admin
    @base = "/admin/products/#{@product.slug}/product_videos"
  end

  teardown { Warden.test_reset! }

  def upload_params(alt: 'teaser')
    { product_video: { alt: alt,
                       video: media_upload(MP4_BYTES, 'clip.mp4', 'video/mp4'),
                       poster: media_upload(PNG_BYTES, 'poster.png', 'image/png') } }
  end

  test 'admin sees the index with the help text and the tab' do
    login_as(@admin, scope: :spree_user)
    media_video(@product, alt: 'listed clip')
    get @base
    assert_response :success
    assert_includes response.body, 'listed clip'
    assert_includes response.body, %(href="http://www.example.com#{@base}")
    get "#{@base}/new"
    assert_response :success
    assert_includes response.body, 'WebM does not play on iOS'
    assert_includes response.body, '15 MB'
  end

  test 'the product edit page links to the Videos tab' do
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{@product.slug}/edit"
    assert_response :success
    assert_includes response.body, @base
  end

  test 'admin creates a video' do
    login_as(@admin, scope: :spree_user)
    assert_difference -> { @product.videos.count }, 1 do
      post @base, params: upload_params
    end
    assert_redirected_to "http://www.example.com#{@base}"
    video = @product.videos.last
    assert_equal 'teaser', video.alt
    assert_equal 'video/mp4', video.video.content_type
    assert_equal 'image/png', video.poster.content_type
  end

  test 'create without a poster re-renders the form with an error' do
    login_as(@admin, scope: :spree_user)
    params = upload_params
    params[:product_video].delete(:poster)
    assert_no_difference -> { Spree::ProductVideo.count } do
      post @base, params: params
    end
    assert_response :success
    assert_includes response.body, 'Poster'
  end

  test 'admin edits alt text without re-uploading' do
    login_as(@admin, scope: :spree_user)
    video = media_video(@product)
    get "#{@base}/#{video.id}/edit"
    assert_response :success
    patch "#{@base}/#{video.id}", params: { product_video: { alt: 'renamed' } }
    assert_redirected_to "http://www.example.com#{@base}"
    assert_equal 'renamed', video.reload.alt
    assert video.video.attached?
  end

  test 'admin destroys a video' do
    login_as(@admin, scope: :spree_user)
    video = media_video(@product)
    assert_difference -> { Spree::ProductVideo.count }, -1 do
      delete "#{@base}/#{video.id}"
    end
    assert_redirected_to "http://www.example.com#{@base}"
  end

  test 'admin reorders videos' do
    login_as(@admin, scope: :spree_user)
    first = media_video(@product, alt: 'first')
    second = media_video(@product, alt: 'second')
    post "#{@base}/update_positions", params: { positions: { first.id => 2, second.id => 1 } }, xhr: true
    assert_response :success
    assert_equal %w[second first], @product.videos.reload.map(&:alt)
  end

  test 'reordering ignores videos of another product' do
    login_as(@admin, scope: :spree_user)
    other = media_video(media_product)
    post "#{@base}/update_positions", params: { positions: { other.id => 5 } }, xhr: true
    assert_equal 1, other.reload.position
  end

  test 'a video of another product cannot be edited through this product' do
    login_as(@admin, scope: :spree_user)
    other = media_video(media_product, alt: 'not yours')
    patch "#{@base}/#{other.id}", params: { product_video: { alt: 'hijacked' } }
    assert_equal 'not yours', other.reload.alt
  end

  # The app answers anonymous requests with its login page (status 200), so check the content.
  test 'anonymous visitors are refused' do
    video = media_video(@product, alt: 'secret clip')
    get @base
    refute_includes response.body, 'secret clip'
    refute_includes response.body, 'product_videos_table'
    assert_no_difference -> { Spree::ProductVideo.count } do
      post @base, params: upload_params
    end
    delete "#{@base}/#{video.id}"
    assert Spree::ProductVideo.exists?(video.id)
  end

  test 'signed-in non-admins are refused' do
    user = Spree.user_class.create!(email: "plain-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    login_as(user, scope: :spree_user)
    video = media_video(@product, alt: 'secret clip')
    get @base
    refute_includes response.body, 'secret clip'
    assert_no_difference -> { Spree::ProductVideo.count } do
      post @base, params: upload_params
    end
    delete "#{@base}/#{video.id}"
    assert Spree::ProductVideo.exists?(video.id)
  end
end
