require 'test_helper'

# Storefront API media contract: extra image attributes and product videos.
class StorefrontProductMediaTest < ActionDispatch::IntegrationTest
  IMAGE_KEYS = %w[viewable_type viewable_id styles alt position content_type width height byte_size
                  animated animated_url].freeze
  VIDEO_KEYS = %w[url content_type byte_size alt position poster_url poster_thumb_url].freeze

  setup do
    @product = media_product(name: 'Media Device')
    @gif = media_image(@product.master, GIF_BYTES, 'anim.gif', 'image/gif', width: 800, height: 500)
    @jpg = media_image(@product.master, JPG_BYTES, 'card.jpg', 'image/jpeg', width: 2, height: 2)
  end

  def included(type)
    Array(media_json['included']).select { |r| r['type'] == type }
  end

  def image_attrs(image)
    included('image').find { |r| r['id'] == image.id.to_s }&.fetch('attributes')
  end

  test 'a GIF is animated and carries the original as animated_url' do
    get "/api/v2/storefront/products/#{@product.slug}?include=images"
    assert_response :success
    attrs = image_attrs(@gif)
    assert_equal true, attrs['animated']
    assert_match %r{\A/rails/active_storage/blobs/redirect/[^/]+/anim\.gif\z}, attrs['animated_url']
    assert_equal 'image/gif', attrs['content_type']
    assert_equal 800, attrs['width']
    assert_equal 500, attrs['height']
    assert_equal GIF_BYTES.bytesize, attrs['byte_size']
    assert_equal 'alt anim.gif', attrs['alt']
    assert_equal 1, attrs['position']
  end

  test 'a JPG is not animated and has no animated_url' do
    get "/api/v2/storefront/products/#{@product.slug}?include=images"
    attrs = image_attrs(@jpg)
    assert_equal false, attrs['animated']
    assert attrs.key?('animated_url')
    assert_nil attrs['animated_url']
    assert_equal 'image/jpeg', attrs['content_type']
    assert_equal 2, attrs['position']
  end

  test 'image attributes are the documented set: styles unchanged and no original_url' do
    get "/api/v2/storefront/products/#{@product.slug}?include=images"
    [@gif, @jpg].each do |image|
      attrs = image_attrs(image)
      assert_equal IMAGE_KEYS.sort, attrs.keys.sort
      refute attrs.key?('original_url')
      assert_equal JSON.parse(image.styles.to_json), attrs['styles']
      # GIF styles stay processed variants (frame 0 posters), never the original blob.
      attrs['styles'].each { |style| assert_match %r{/rails/active_storage/representations/}, style['url'] }
    end
  end

  test 'an image without blob metadata reports null dimensions' do
    bare = media_image(@product.master, JPG_BYTES, 'bare.jpg', 'image/jpeg')
    get "/api/v2/storefront/products/#{@product.slug}?include=images"
    attrs = image_attrs(bare)
    assert_nil attrs['width']
    assert_nil attrs['height']
  end

  test 'products index with include=videos,images returns videos with poster urls' do
    first = media_video(@product, alt: 'first')
    second = media_video(@product, alt: 'second')
    second.insert_at(1)

    get '/api/v2/storefront/products?include=videos,images'
    assert_response :success
    product = media_json['data'].find { |p| p['id'] == @product.id.to_s }
    assert_equal [second.id.to_s, first.id.to_s], product['relationships']['videos']['data'].map { |r| r['id'] }
    assert_equal %w[product_video], product['relationships']['videos']['data'].map { |r| r['type'] }.uniq

    videos = included('product_video')
    assert_equal 2, videos.size
    attrs = videos.find { |v| v['id'] == first.id.to_s }['attributes']
    assert_equal VIDEO_KEYS.sort, attrs.keys.sort
    assert_match %r{\A/rails/active_storage/blobs/redirect/[^/]+/clip\.mp4\z}, attrs['url']
    assert_match %r{\A/rails/active_storage/representations/redirect/[^/]+/[^/]+/poster\.png\z}, attrs['poster_url']
    assert_match %r{\A/rails/active_storage/representations/redirect/[^/]+/[^/]+/poster\.png\z}, attrs['poster_thumb_url']
    assert_equal 'video/mp4', attrs['content_type']
    assert_equal MP4_BYTES.bytesize, attrs['byte_size']
    assert_equal 'first', attrs['alt']
    assert_equal 2, attrs['position']
    assert included('image').any?
  end

  test 'a product without videos has an empty videos relationship' do
    get "/api/v2/storefront/products/#{@product.slug}?include=videos"
    assert_response :success
    assert_equal [], media_json['data']['relationships']['videos']['data']
  end

  test 'requests without include=videos are unchanged' do
    media_video(@product)
    get "/api/v2/storefront/products/#{@product.slug}"
    assert_response :success
    assert_nil media_json['included']
  end

  test 'mp4 and webm are allowed inline' do
    assert_includes ActiveStorage.content_types_allowed_inline, 'video/mp4'
    assert_includes ActiveStorage.content_types_allowed_inline, 'video/webm'
    # Rails' own defaults are kept.
    assert_includes ActiveStorage.content_types_allowed_inline, 'image/gif'
    # The blob no longer forces Content-Disposition: attachment on the service URL.
    %w[video/mp4 video/webm].each do |type|
      blob = media_blob(MP4_BYTES, 'clip.mp4', type)
      assert_nil blob.forced_disposition_for_serving
    end
  end
end
