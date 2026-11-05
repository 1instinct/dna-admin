# Shared helpers for the product media and featured-collection tests.
module ShopMediaTestHelper
  # Tiny but real files, so content type sniffing (Marcel) sees genuine magic bytes.
  # 2x2, two frames, looping.
  GIF_BYTES = Base64.decode64(
    'R0lGODlhAgACAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAAAAAACwAAAAAAgACAAACAoRRACH5BAAAAAAALAAAAAAC' \
    'AAIAgAAA/wAAAAIChFEAOw=='
  ).freeze
  # 1x1 white.
  PNG_BYTES = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQAAAAA3bvkkAAAACklEQVQI12NoAAAAggCB3UNq9AAAAABJRU5ErkJggg==').freeze
  # 2x2 green.
  JPG_BYTES = Base64.decode64(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19i' \
    'Z2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2Nj' \
    'Y2NjY2NjY2P/wAARCAACAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QA' \
    'FAEBAAAAAAAAAAAAAAAAAAAABf/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AIgAsM//2Q=='
  ).freeze
  # ISO BMFF header (ftyp box) followed by padding: enough for an mp4 sniff.
  MP4_BYTES = ("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b + ("\x00".b * 64)).freeze
  # EBML header with the "webm" doctype.
  WEBM_BYTES = ("\x1A\x45\xDF\xA3\x9F\x42\x86\x81\x01\x42\xF7\x81\x01\x42\xF2\x81\x04\x42\xF3\x81\x08" \
                "\x42\x82\x84webm\x42\x87\x81\x02\x42\x85\x81\x02".b + ("\x00".b * 64)).freeze

  def media_store
    store = Spree::Store.default
    return store if store.persisted?

    Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "test-#{SecureRandom.hex(3)}",
                         mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
  end

  def media_product(name: "Media Product #{SecureRandom.hex(3)}", available_on: 1.day.ago, price: 10)
    shipping_category = Spree::ShippingCategory.first_or_create!(name: 'Default')
    product = Spree::Product.new(name: name, price: price, available_on: available_on,
                                 shipping_category: shipping_category)
    product.stores << media_store if product.respond_to?(:stores)
    product.save!
    product
  end

  # A blob uploaded to the test service, with metadata set up front so no analyze job is needed.
  def media_blob(bytes, filename, content_type, metadata = {})
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: filename, content_type: content_type,
                                           metadata: metadata.merge(analyzed: true))
  end

  def media_image(viewable, bytes, filename, content_type, metadata = {})
    image = Spree::Image.new(viewable: viewable, alt: "alt #{filename}")
    image.attachment.attach(media_blob(bytes, filename, content_type, metadata))
    image.save!
    image
  end

  def media_video(product, alt: 'clip')
    video = Spree::ProductVideo.new(product: product, alt: alt)
    video.video.attach(media_blob(MP4_BYTES, 'clip.mp4', 'video/mp4'))
    video.poster.attach(media_blob(PNG_BYTES, 'poster.png', 'image/png', width: 1, height: 1))
    video.save!
    video
  end

  # A Rack upload built from raw bytes, as an admin form would post it.
  def media_upload(bytes, filename, content_type)
    file = Tempfile.new(['media', File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  def media_admin
    user = Spree.user_class.create!(email: "media-admin-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  def media_json
    JSON.parse(response.body)
  end
end

ActiveSupport::TestCase.include(ShopMediaTestHelper)
