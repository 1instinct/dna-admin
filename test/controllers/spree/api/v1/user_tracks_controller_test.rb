require 'test_helper'

# /api/v1/user_tracks: the signed-in user's AI backing tracks (OAuth bearer).
class Spree::Api::V1::UserTracksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    setup_user_tracks
    @user = create(:user)
    @headers = auth(@user)
  end

  teardown { reset_user_tracks! }

  def make(request = track_request, headers = @headers)
    post '/api/v1/user_tracks', params: request, headers: headers, as: :json
  end

  def finish(track)
    track.update!(status: 'ready', ready_at: Time.current)
  end

  test 'every endpoint needs a bearer' do
    get '/api/v1/user_tracks'
    assert_response :unauthorized
    make(track_request, {})
    assert_response :unauthorized
    get '/api/v1/user_tracks/styles'
    assert_response :unauthorized
  end

  test 'create validates, debits one credit and answers 201 queued' do
    assert_difference -> { Spree::UserTrack.count }, 1 do
      make
    end
    assert_response :created
    track = Spree::UserTrack.last
    assert_equal @user, track.user
    assert_equal 'queued', json['status']
    assert_equal track.id.to_s, json['id']
    assert_equal 'Chillhop in A minor', json['title']
    assert_equal track_request, json['request']
    assert_nil json['profile']
    assert_nil json['loop']
    assert_nil json['readyAt']
    assert json['createdAt'].present?
    assert_equal 19, UserTracks::Quota.remaining(@user)
    assert_equal '19', response.headers['X-Quota-Remaining']
  end

  test 'create refuses a bad request with 422 and fields, without a debit' do
    assert_no_difference -> { Spree::UserTrack.count } do
      make(track_request('bars' => 12, 'style' => 'polka'))
    end
    assert_response :unprocessable_entity
    assert json['fields']['bars'].present?
    assert json['fields']['style'].present?
  end

  test 'a second create while one is in flight is 409' do
    make
    assert_response :created
    assert_no_difference -> { Spree::UserTrack.count } do
      make
    end
    assert_response :conflict
    assert_equal 'in_flight', json['error']
  end

  test 'a finished or deleted track is not in flight' do
    finish(create_user_track(@user))
    deleted = create_user_track(@user)
    UserTracks::Removal.call(deleted)
    make
    assert_response :created
  end

  test 'quota exhausted is 402 quota' do
    UserTracks.config.monthly_free = 1
    finish(create_user_track(@user))
    assert_no_difference -> { Spree::UserTrack.count } do
      make
    end
    assert_response :payment_required
    assert_equal 'quota', json['error']
  end

  test 'more than the hourly limit of creates is 429, deleted tracks included' do
    UserTracks.config.hourly_limit = 2
    2.times { UserTracks::Removal.call(create_user_track(@user)) }
    make
    assert_response :too_many_requests
    assert_equal 'rate_limited', json['error']
  end

  test 'index lists only the owner\'s live tracks, newest first' do
    old = create_user_track(@user, created_at: 2.hours.ago)
    new = create_user_track(@user, created_at: 1.hour.ago)
    UserTracks::Removal.call(create_user_track(@user))
    create_user_track(create(:user))

    get '/api/v1/user_tracks', headers: @headers
    assert_response :ok
    assert_equal [new.id.to_s, old.id.to_s], json.map { |t| t['id'] }
    assert_equal '17', response.headers['X-Quota-Remaining']
  end

  test 'show answers the owner\'s track and 404 for anyone else\'s' do
    mine = create_user_track(@user)
    theirs = create_user_track(create(:user))
    get "/api/v1/user_tracks/#{mine.id}", headers: @headers
    assert_response :ok
    assert_equal mine.id.to_s, json['id']
    get "/api/v1/user_tracks/#{theirs.id}", headers: @headers
    assert_response :not_found
  end

  test 'a ready track carries its profile, loop and keyNote' do
    track = create_user_track(@user)
    track.update!(status: 'ready', ready_at: Time.current, loop_info: { 'sampleRate' => 48_000, 'loopSamples' => 1_843_200 },
                  profile: { 'bpm' => 100, 'key' => 5, 'scale' => 'major', 'keyNote' => 'Came out in F major',
                             'profileSource' => { 'bpm' => 'requested', 'key' => 'measured' } })
    get "/api/v1/user_tracks/#{track.id}", headers: @headers
    assert_equal 'ready', json['status']
    assert_equal 5, json['profile']['key']
    assert_equal({ 'sampleRate' => 48_000, 'loopSamples' => 1_843_200 }, json['loop'])
    assert_equal 'Came out in F major', json['keyNote']
    assert json['readyAt'].present?
  end

  test 'destroy removes the track and purges its audio' do
    track = create_user_track(@user)
    track.audio.attach(io: StringIO.new('fLaC-bytes'), filename: 'loop.flac', content_type: 'audio/flac')
    blob = track.audio.blob
    delete "/api/v1/user_tracks/#{track.id}", headers: @headers
    assert_response :no_content
    refute ActiveStorage::Blob.exists?(blob.id)
    assert track.reload.deleted_at
    get "/api/v1/user_tracks/#{track.id}", headers: @headers
    assert_response :not_found
    delete "/api/v1/user_tracks/#{track.id}", headers: @headers
    assert_response :not_found
  end

  test 'audio redirects a ready track to a short-lived signed URL, never logged' do
    track = create_user_track(@user)
    track.audio.attach(io: StringIO.new('fLaC-bytes'), filename: 'loop.flac', content_type: 'audio/flac')
    finish(track)

    log = captured_log { get "/api/v1/user_tracks/#{track.id}/audio", headers: @headers }
    assert_response :found
    location = response.headers['Location']
    assert_match %r{/rails/active_storage/disk/}, location
    assert_equal 'no-store', response.headers['Cache-Control']
    signed = location.split('/rails/active_storage/disk/').last.split('/').first
    assert_includes log, "/api/v1/user_tracks/#{track.id}/audio" # the request itself was logged
    refute_includes log, signed
  end

  test 'audio is 404 until the track is ready, and for other users' do
    track = create_user_track(@user)
    track.audio.attach(io: StringIO.new('fLaC-bytes'), filename: 'loop.flac', content_type: 'audio/flac')
    get "/api/v1/user_tracks/#{track.id}/audio", headers: @headers
    assert_response :not_found

    finish(track)
    get "/api/v1/user_tracks/#{track.id}/audio", headers: auth(create(:user))
    assert_response :not_found
  end

  test 'styles and moods answer the vocabulary' do
    get '/api/v1/user_tracks/styles', headers: @headers
    assert_response :ok
    assert_equal %w[chillhop synthpop], json.map { |s| s['id'] }
    assert_equal({ 'id' => 'chillhop', 'label' => 'Chillhop', 'bpmRange' => [80, 96], 'defaultMoods' => ['warm'],
                   'caption' => 'chillhop beat, dusty boom bap drums, warm electric piano chords, round bass' },
                 json.first)

    get '/api/v1/user_tracks/moods', headers: @headers
    assert_response :ok
    assert_equal [{ 'id' => 'warm', 'label' => 'Warm' }, { 'id' => 'dark', 'label' => 'Dark' },
                  { 'id' => 'driving', 'label' => 'Driving' }], json
  end

  test 'quota answers what is left this month' do
    create_user_track(@user)
    get '/api/v1/user_tracks/quota', headers: @headers
    assert_response :ok
    assert_equal 19, json['remaining']
    assert_equal 20, json['monthlyFree']
    assert_equal Time.current.utc.beginning_of_month.next_month.iso8601, json['resetsAt']
  end

  test 'variation copies the request into a new track and debits a credit' do
    source = create_user_track(@user, request: { 'bars' => 32, 'moods' => ['dark'] })
    finish(source)
    assert_difference -> { Spree::UserTrack.count }, 1 do
      post "/api/v1/user_tracks/#{source.id}/variation", headers: @headers, as: :json
    end
    assert_response :created
    variation = Spree::UserTrack.last
    refute_equal source.id, variation.id
    assert_equal source.request, variation.request
    assert_equal 'queued', variation.status
    assert_equal 18, UserTracks::Quota.remaining(@user)
  end

  test 'variation of someone else\'s track is 404; while one is in flight it is 409' do
    theirs = create_user_track(create(:user))
    post "/api/v1/user_tracks/#{theirs.id}/variation", headers: @headers, as: :json
    assert_response :not_found

    mine = create_user_track(@user)
    post "/api/v1/user_tracks/#{mine.id}/variation", headers: @headers, as: :json
    assert_response :conflict
  end
end
