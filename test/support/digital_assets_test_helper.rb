# Shared helpers for the digital assets and ownership tests.
module DigitalAssetsTestHelper
  WAV_BYTES = ('RIFF'.b + [36].pack('V') + 'WAVEfmt '.b + [16, 1, 1, 48_000, 96_000, 2, 16].pack('VvvVVvv') +
               'data'.b + [0].pack('V')).freeze

  def self.store
    store = Spree::Store.default
    return store if store.persisted?

    Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "test-#{SecureRandom.hex(3)}",
                         mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
  end

  def digital_store
    DigitalAssetsTestHelper.store
  end

  # A blob in the test service, with metadata set so no analyze job is needed.
  def digital_blob(bytes = WAV_BYTES, filename = "file-#{SecureRandom.hex(3)}.wav", content_type = 'audio/wav')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: filename, content_type: content_type,
                                           metadata: { analyzed: true })
  end

  # A published asset on a new product's master variant.
  def published_asset(price: 10, kind: 'pack', files: { 'kick.wav' => WAV_BYTES }, manifest: {}, product: nil)
    product ||= create(:digital_product, price: price)
    asset = Spree::DigitalAsset.create!(variant: product.master, kind: kind, manifest: manifest)
    asset.attach_files!(files.map { |name, bytes| digital_blob(bytes, name) })
    asset.publish!
    asset
  end
end

ActiveSupport::TestCase.include(DigitalAssetsTestHelper)
