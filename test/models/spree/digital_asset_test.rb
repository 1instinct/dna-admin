require 'test_helper'

class Spree::DigitalAssetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  teardown { DigitalAssets.reset_config! }

  def asset_with_file(variant, kind: 'pack')
    asset = Spree::DigitalAsset.create!(variant: variant, kind: kind)
    asset.attach_files!([digital_blob(DigitalAssetsTestHelper::WAV_BYTES, 'kick.wav')])
    asset
  end

  test 'publish! assigns version max+1 per variant' do
    variant = create(:digital_product).master
    other = create(:digital_product).master

    first = asset_with_file(variant)
    assert_nil first.version
    assert first.draft?

    first.publish!
    assert_equal 1, first.reload.version
    assert first.published?

    second = asset_with_file(variant)
    second.publish!
    assert_equal 2, second.reload.version

    assert_equal 1, asset_with_file(other).tap(&:publish!).version
    # Publishing retires nothing; the live asset is the highest published version.
    assert first.reload.published?
    assert_equal second, variant.reload.live_digital_asset
  end

  test 'publish! refuses an asset without files' do
    asset = create(:digital_asset)
    assert_raises(ActiveRecord::RecordInvalid) { asset.publish! }
    assert asset.reload.draft?
    assert_nil asset.version
  end

  test 'publishing an already published asset keeps its version' do
    asset = asset_with_file(create(:digital_product).master)
    asset.publish!
    asset.publish!
    assert_equal 1, asset.reload.version
  end

  test 'kind not in configured kinds is invalid when kinds is non-empty' do
    asset = build(:digital_asset, kind: 'anything')
    assert asset.valid?, 'any kind is allowed while kinds is empty'

    DigitalAssets.config.kinds = %w[pack preset]
    refute asset.valid?
    assert asset.errors[:kind].any?
    asset.kind = 'preset'
    assert asset.valid?
  end

  test 'manifest validator errors are added to errors[:manifest]' do
    seen = []
    DigitalAssets.config.manifest_validators['pack'] = lambda do |manifest, asset|
      seen << asset
      manifest['format'] == 1 ? [] : ['format must be 1', 'samples missing']
    end

    asset = build(:digital_asset, kind: 'pack', manifest: { 'format' => 2 })
    refute asset.valid?
    assert_equal ['format must be 1', 'samples missing'], asset.errors[:manifest]
    assert_equal [asset], seen

    asset.manifest = { 'format' => 1 }
    assert asset.valid?
  end

  test 'a one-argument validator gets the manifest only' do
    DigitalAssets.config.manifest_validators['pack'] = ->(manifest) { manifest.empty? ? ['empty'] : [] }
    refute build(:digital_asset, manifest: {}).valid?
  end

  test 'manifest must be an object' do
    asset = build(:digital_asset, manifest: [1, 2])
    refute asset.valid?
    assert asset.errors[:manifest].any?
  end

  test 'byte_size is the sum of the files and file_entries describe each file' do
    asset = Spree::DigitalAsset.create!(variant: create(:digital_product).master, kind: 'pack')
    asset.attach_files!([digital_blob('a' * 10, 'a.wav'), digital_blob('b' * 5, 'b.json', 'application/json')])

    assert_equal 15, asset.reload.byte_size
    entries = asset.file_entries.sort_by { |e| e[:filename] }
    assert_equal %w[a.wav b.json], entries.map { |e| e[:filename] }
    assert_equal [10, 5], entries.map { |e| e[:byte_size] }
    assert_equal 'application/json', entries.last[:content_type]
    assert_equal Digest::MD5.base64digest('a' * 10), entries.first[:md5]
    assert entries.all? { |e| e[:id].is_a?(Integer) }
    assert entries.all? { |e| e.key?(:sha256) }
  end

  test 'attach_files! enqueues the checksum job, which stores sha256 per file in manifest files' do
    asset = Spree::DigitalAsset.create!(variant: create(:digital_product).master, kind: 'pack', manifest: { 'format' => 1 })
    assert_enqueued_with(job: DigitalAssets::ChecksumJob) do
      asset.attach_files!([digital_blob('hello', 'a.wav')])
    end
    perform_enqueued_jobs

    asset.reload
    assert_equal 1, asset.manifest['format']
    entry = asset.file_entries.first
    assert_equal Digest::SHA256.hexdigest('hello'), entry[:sha256]
    assert_equal [{ 'id' => entry[:id], 'filename' => 'a.wav', 'sha256' => Digest::SHA256.hexdigest('hello') }],
                 asset.manifest['files']
  end

  test 'a digital variant tracks no stock but keeps its track_inventory setting' do
    variant = asset_with_file(create(:digital_product).master).tap(&:publish!).variant
    variant = Spree::Variant.find(variant.id)
    assert variant[:track_inventory]
    assert variant.track_inventory, 'the admin form shows the saved setting'
    refute variant.should_track_inventory?

    variant.update!(sku: 'SAVED-1')
    assert variant.reload[:track_inventory], 'saving the variant keeps the column'
  end

  test 'digital? is answered once per variant instance and follows publish' do
    variant = create(:digital_product).master
    asset = asset_with_file(variant)
    variant = Spree::Variant.find(variant.id)
    refute variant.digital?

    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { 3.times { variant.digital? } }
    assert_equal 0, queries

    asset.publish!
    assert asset.variant.digital?, 'the asset clears its own variant'
    assert variant.reload.digital?
  end

  test 'attach_files! adds to the files already attached' do
    asset = Spree::DigitalAsset.create!(variant: create(:digital_product).master, kind: 'pack')
    asset.attach_files!([digital_blob('aa', 'a.wav')])
    asset = Spree::DigitalAsset.find(asset.id)
    asset.attach_files!([digital_blob('bbb', 'b.wav')])

    asset.reload
    assert_equal %w[a.wav b.wav], asset.file_entries.map { |f| f[:filename] }
    assert_equal 5, asset.byte_size
    assert_equal 2, ActiveStorage::Attachment.where(record: asset).count
  end

  test 'file names are unique within an asset' do
    asset = Spree::DigitalAsset.create!(variant: create(:digital_product).master, kind: 'pack')
    asset.attach_files!([digital_blob('a', 'same.wav')])
    assert_raises(ActiveRecord::RecordInvalid) { asset.attach_files!([digital_blob('b', 'same.wav')]) }
  end
end
