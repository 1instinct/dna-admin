require 'test_helper'
require 'rake'

# POST /api/v1/uploads: a direct-upload slot for one file.
class Spree::Api::V1::UploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @headers = auth(@user)
  end

  teardown { Uploads.reset_config! }

  def params_for(filename: 'kick.wav', byte_size: 1234, content_type: 'audio/wav', checksum: Digest::MD5.base64digest('x'))
    { filename: filename, byte_size: byte_size, checksum: checksum, content_type: content_type }
  end

  test 'uploads returns signed_id and direct_upload url+headers' do
    post '/api/v1/uploads', params: params_for, headers: @headers, as: :json
    assert_response :created

    blob = ActiveStorage::Blob.find_signed!(json['signed_id'])
    assert_equal 'kick.wav', blob.filename.to_s
    assert_equal 1234, blob.byte_size
    assert_equal 'audio/wav', blob.content_type
    assert_match %r{\Ahttp://www.example.com/rails/active_storage/disk/}, json['direct_upload']['url']
    assert_equal 'audio/wav', json['direct_upload']['headers']['Content-Type']
  end

  test 'each rule accepts its types up to its size' do
    {
      ['pad.aiff', 'audio/aiff', 50.megabytes] => :created,
      ['pad.flac', 'audio/flac', 1] => :created,
      ['pad.mp3', 'audio/mpeg', 1] => :created,
      ['cover.png', 'image/png', 10.megabytes] => :created,
      ['cover.jpg', 'image/jpeg', 1] => :created,
      ['cover.webp', 'image/webp', 1] => :created,
      ['manifest.json', 'application/json', 256.kilobytes] => :created,
      ['scene.glsl', 'text/plain', 1] => :created,
      ['scene.glsl', 'application/octet-stream', 1] => :created
    }.each do |(name, type, size), status|
      post '/api/v1/uploads', params: params_for(filename: name, content_type: type, byte_size: size), headers: @headers, as: :json
      assert_response status, "#{name} #{type} #{size}: #{response.body}"
    end
  end

  test 'uploads rejects unknown content type and oversize with 422' do
    [
      params_for(filename: 'run.exe', content_type: 'application/x-msdownload'),
      params_for(filename: 'kick.wav', content_type: 'application/octet-stream'),
      params_for(filename: 'kick.exe', content_type: 'audio/wav'),
      params_for(filename: 'kick.wav', byte_size: 50.megabytes + 1),
      params_for(filename: 'cover.png', content_type: 'image/png', byte_size: 10.megabytes + 1),
      params_for(filename: 'scene.glsl', content_type: 'text/plain', byte_size: 256.kilobytes + 1),
      params_for(byte_size: 0),
      params_for(checksum: 'not-md5'),
      params_for(filename: '')
    ].each do |params|
      assert_no_difference -> { ActiveStorage::Blob.count } do
        post '/api/v1/uploads', params: params, headers: @headers, as: :json
      end
      assert_response :unprocessable_entity, params.inspect
      assert json['error'].present?
    end
  end

  test 'uploads are rate limited per user' do
    Uploads.config.rate_limit = { limit: 1, window: 1.hour }
    post '/api/v1/uploads', params: params_for, headers: @headers, as: :json
    assert_response :created
    post '/api/v1/uploads', params: params_for, headers: @headers, as: :json
    assert_response :too_many_requests
  end

  test 'the default limit is 100 upload slots an hour' do
    assert_equal({ limit: 100, window: 1.hour }, Uploads.config.rate_limit)
  end

  test 'the sweep purges unattached blobs older than a day only' do
    old_loose = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a'), filename: 'a.wav', content_type: 'audio/wav')
    old_loose.update_columns(created_at: 2.days.ago)
    new_loose = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('b'), filename: 'b.wav', content_type: 'audio/wav')
    asset = published_asset
    asset.files.blobs.each { |b| b.update_columns(created_at: 2.days.ago) }

    assert_equal 1, Uploads::UnattachedSweeper.call
    refute ActiveStorage::Blob.exists?(old_loose.id)
    assert ActiveStorage::Blob.exists?(new_loose.id)
    assert_equal 1, asset.reload.files.count
  end

  test 'the uploads:sweep_unattached task runs the sweep' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('uploads:sweep_unattached')
    loose = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a'), filename: 'a.wav', content_type: 'audio/wav')
    loose.update_columns(created_at: 2.days.ago)
    Rake::Task['uploads:sweep_unattached'].reenable
    assert_output(/1/) { Rake::Task['uploads:sweep_unattached'].invoke }
    refute ActiveStorage::Blob.exists?(loose.id)
  end

  test 'all endpoints 401 without bearer' do
    post '/api/v1/uploads', params: params_for, as: :json
    assert_response :unauthorized
  end
end
