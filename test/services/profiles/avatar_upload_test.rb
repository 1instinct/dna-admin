require 'test_helper'
require 'zlib'

# The decompression-bomb guard must read the size from the header, before anything decodes it.
class Profiles::AvatarUploadTest < ActiveSupport::TestCase
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  def png_chunk(type, data)
    [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
  end

  def png_header(width, height)
    PNG_SIGNATURE + png_chunk('IHDR', [width, height, 8, 0, 0, 0, 0].pack('NNCCCCC'))
  end

  # A valid grayscale PNG of zero pixels: small on disk, huge once decoded.
  def png_bomb(width, height)
    row = "\0" * (width + 1)
    deflate = Zlib::Deflate.new(Zlib::BEST_SPEED)
    data = +''.b
    height.times { data << deflate.deflate(row) }
    data << deflate.finish
    png_header(width, height) + png_chunk('IDAT', data) + png_chunk('IEND', ''.b)
  end

  setup do
    @profile = create(:user_profile, handle: 'bomb_target')
  end

  test 'dimensions come from the header: a PNG with no usable pixel data still reports its size' do
    png = png_header(30_000, 30_000) + png_chunk('IDAT', Zlib.deflate('')) + png_chunk('IEND', ''.b)
    file = bytes_upload(png, 'image/png', 'huge.png')

    assert_equal [30_000, 30_000], Profiles::AvatarUpload.new(@profile, file).send(:header_dimensions)
  end

  test 'an image over the pixel limit is refused without being processed' do
    file = bytes_upload(png_bomb(5000, 5000), 'image/png', 'bomb.png')
    assert_operator file.size, :<, 1.megabyte

    upload = Profiles::AvatarUpload.new(@profile, file)
    assert_equal [5000, 5000], upload.send(:header_dimensions)
    processor = ImageProcessing::MiniMagick
    processor.define_singleton_method(:source) { |*| raise 'decoded the image' }

    error = assert_raises(Profiles::AvatarUpload::Error) { upload.call }

    assert_equal 422, error.status
    refute @profile.reload.avatar.attached?
  ensure
    processor&.singleton_class&.send(:remove_method, :source)
  end

  test 'the pixel limit is about 16 megapixels' do
    assert_equal 16_000_000, Profiles::AvatarUpload::MAX_PIXELS
  end

  test 'an image under the limit is stored as the configured square JPEG' do
    Profiles::AvatarUpload.call(@profile, fixture_upload('avatar.png', 'image/png'))

    blob = @profile.reload.avatar.blob
    assert_equal 'image/jpeg', blob.content_type
    assert_equal 'avatar.jpg', blob.filename.to_s
  end

  test 'a large photo just under the limit still processes within the resource limits' do
    file = bytes_upload(png_bomb(3900, 3900), 'image/png', 'big.png')

    Profiles::AvatarUpload.call(@profile, file)

    assert @profile.reload.avatar.attached?
  end

  test 'every ImageMagick command carries explicit resource limits' do
    %i[memory map disk time].each { |resource| assert Profiles::AvatarUpload::MAGICK_LIMITS.key?(resource), resource }

    commands = []
    subscriber = ActiveSupport::Notifications.subscribe('mini_magick.tool') { |*args| commands << args.last }
    MiniMagick::Shell.class_eval do
      alias_method :__run, :run
      define_method(:run) do |command, *rest|
        ActiveSupport::Notifications.instrument('mini_magick.tool', command)
        __run(command, *rest)
      end
    end

    Profiles::AvatarUpload.call(@profile, fixture_upload('avatar.png', 'image/png'))

    # Active Storage then analyses the stored copy, which is our own 1024 px JPEG.
    on_upload = commands.reject { |command| command.join(' ').include?('ActiveStorage-') }
    assert_operator on_upload.size, :>=, 2, 'identify and convert'
    on_upload.each do |command|
      assert_includes command, '-limit', command.join(' ')
      assert_includes command, 'memory', command.join(' ')
    end
    assert_includes on_upload.first, '-ping'
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    MiniMagick::Shell.class_eval do
      alias_method :run, :__run
      remove_method :__run
    end
  end
end
