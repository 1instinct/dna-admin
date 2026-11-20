require 'test_helper'

class Spree::ProductVideoTest < ActiveSupport::TestCase
  setup do
    @product = media_product
  end

  def build_video(video: [MP4_BYTES, 'clip.mp4', 'video/mp4'], poster: [PNG_BYTES, 'poster.png', 'image/png'])
    record = Spree::ProductVideo.new(product: @product, alt: 'demo')
    record.video.attach(media_blob(*video)) if video
    record.poster.attach(media_blob(*poster)) if poster
    record
  end

  # A blob row that claims a size, without uploading that many bytes. Marked identified and
  # analyzed so attaching it doesn't try to download the (absent) file.
  def sized_blob(filename, content_type, byte_size)
    ActiveStorage::Blob.create_before_direct_upload!(filename: filename, byte_size: byte_size,
                                                     checksum: Digest::MD5.base64digest(filename),
                                                     content_type: content_type,
                                                     metadata: { identified: true, analyzed: true })
  end

  test 'valid with an mp4 and a png poster' do
    assert build_video.valid?
  end

  test 'webm video and jpeg or webp posters are accepted' do
    assert build_video(video: [WEBM_BYTES, 'clip.webm', 'video/webm']).valid?
    assert build_video(poster: [JPG_BYTES, 'poster.jpg', 'image/jpeg']).valid?
    webp = build_video(poster: nil)
    webp.poster.attach(sized_blob('poster.webp', 'image/webp', 1000))
    assert webp.valid?, webp.errors.full_messages.inspect
  end

  test 'video is required' do
    record = build_video(video: nil)
    refute record.valid?
    assert record.errors[:video].any?
  end

  test 'poster is required' do
    record = build_video(poster: nil)
    refute record.valid?
    assert record.errors[:poster].any?
  end

  test 'product is required' do
    record = build_video
    record.product = nil
    refute record.valid?
    assert record.errors[:product].any?
  end

  test 'video must be mp4 or webm' do
    record = build_video(video: [GIF_BYTES, 'clip.gif', 'image/gif'])
    refute record.valid?
    assert record.errors[:video].any?

    mov = build_video(video: nil)
    mov.video.attach(sized_blob('clip.mov', 'video/quicktime', 1000))
    refute mov.valid?
  end

  test 'poster must be jpeg, png or webp' do
    record = build_video(poster: [GIF_BYTES, 'poster.gif', 'image/gif'])
    refute record.valid?
    assert record.errors[:poster].any?
  end

  test 'video is capped at 50 MB' do
    ok = build_video(video: nil)
    ok.video.attach(sized_blob('ok.mp4', 'video/mp4', 50.megabytes))
    assert ok.valid?

    big = build_video(video: nil)
    big.video.attach(sized_blob('big.mp4', 'video/mp4', 50.megabytes + 1))
    refute big.valid?
    assert big.errors[:video].any?
  end

  test 'poster is capped at 10 MB' do
    ok = build_video(poster: nil)
    ok.poster.attach(sized_blob('ok.png', 'image/png', 10.megabytes))
    assert ok.valid?

    big = build_video(poster: nil)
    big.poster.attach(sized_blob('big.png', 'image/png', 10.megabytes + 1))
    refute big.valid?
    assert big.errors[:poster].any?
  end

  test 'product has many videos in position order' do
    first = media_video(@product, alt: 'first')
    second = media_video(@product, alt: 'second')
    assert_equal [1, 2], [first.position, second.position]
    second.insert_at(1)
    assert_equal %w[second first], @product.reload.videos.map(&:alt)
  end

  test 'positions are scoped per product' do
    other = media_product
    media_video(@product)
    assert_equal 1, media_video(other).position
  end

  test 'saving a video touches the product' do
    @product.update_columns(updated_at: 2.days.ago)
    before = @product.reload.updated_at
    media_video(@product)
    assert_operator @product.reload.updated_at, :>, before
  end

  # Same as variant images: deleting a product in the admin (a soft delete) removes its media.
  test 'deleting the product destroys its videos' do
    video = media_video(@product)
    @product.destroy
    refute Spree::ProductVideo.exists?(video.id)
  end

  test 'urls are paths to the blob and poster variants' do
    video = media_video(@product)
    assert_match %r{\A/rails/active_storage/blobs/redirect/.+/clip\.mp4\z}, video.video_url
    assert_match %r{\A/rails/active_storage/representations/redirect/.+/poster\.png\z}, video.poster_url
    assert_match %r{\A/rails/active_storage/representations/redirect/.+/poster\.png\z}, video.poster_thumb_url
    refute_equal video.poster_url, video.poster_thumb_url
  end
end
