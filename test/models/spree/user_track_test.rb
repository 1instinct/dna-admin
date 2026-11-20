require 'test_helper'

class Spree::UserTrackTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  def build_track(request)
    Spree::UserTrack.new(user: @user, request: Spree::UserTrack.normalize_request(request))
  end

  test 'a full request is valid and normalized' do
    track = build_track('style' => 'chillhop', 'moods' => %w[warm dark], 'bars' => '16', 'bpm' => '99.6',
                        'key' => '9', 'scale' => 'Minor', 'timeSig' => '4/4')
    assert track.valid?, track.errors.full_messages.inspect
    assert_equal({ 'style' => 'chillhop', 'moods' => %w[warm dark], 'bars' => 16, 'bpm' => 100, 'key' => 9,
                   'scale' => 'minor', 'timeSig' => '4/4' }, track.request)
    assert_equal 4, track.beats_per_bar
  end

  test 'defaults: moods from the style, bpm from the middle of its range, 4/4' do
    track = build_track('style' => 'chillhop', 'bars' => 8, 'key' => 0, 'scale' => 'major')
    assert track.valid?, track.errors.full_messages.inspect
    assert_equal ['warm'], track.request['moods']
    assert_equal 88, track.request['bpm']
    assert_equal '4/4', track.request['timeSig']
  end

  test 'key names and time signature numerators are accepted' do
    track = build_track(track_request('key' => 'Bb', 'timeSig' => 3))
    assert track.valid?, track.errors.full_messages.inspect
    assert_equal 10, track.request['key']
    assert_equal '3/4', track.request['timeSig']
    assert_equal 3, track.beats_per_bar
  end

  test 'each field is validated' do
    {
      'style' => 'polka', 'bars' => 12, 'bpm' => 39, 'key' => 12, 'scale' => 'dorian', 'timeSig' => '5/4'
    }.each do |field, bad|
      track = build_track(track_request(field => bad))
      refute track.valid?, "#{field}=#{bad.inspect} should be invalid"
      assert track.errors[field.to_sym].any?, "#{field}: #{track.errors.to_hash.inspect}"
    end

    refute build_track(track_request('bpm' => 241)).valid?
    refute build_track(track_request('bpm' => 'fast')).valid?
    refute build_track(track_request('bars' => 'sixteen')).valid?
    refute build_track(track_request('key' => -1)).valid?
    refute build_track(track_request('moods' => %w[warm dark driving])).valid?
    refute build_track(track_request('moods' => ['sleepy'])).valid?
    assert build_track(track_request('moods' => [])).valid?
  end

  test 'a length that cannot fit the generator maximum with its spare bars is too long' do
    # (bars + 4) * beats * 60 / bpm must be <= 120 s.
    { [32, 71, '4/4'] => 16, [32, 107, '6/8'] => 16, [16, 59, '6/8'] => 8, [32, 53, '3/4'] => 16 }.
      each do |(bars, bpm, sig), max|
        track = build_track(track_request('bars' => bars, 'bpm' => bpm, 'timeSig' => sig))
        refute track.valid?, "#{bars} bars at #{bpm} in #{sig} should be too long"
        detail = track.errors.details[:bars].find { |d| d[:error] == :too_long }
        assert_equal max, detail[:max_bars], "#{bars} bars at #{bpm} in #{sig}"
        assert_equal max, Spree::UserTrack.max_bars(bpm, track.beats_per_bar)
      end

    [[32, 72, '4/4'], [32, 108, '6/8'], [16, 60, '6/8'], [8, 40, '6/8'], [32, 40, '2/4']].each do |bars, bpm, sig|
      track = build_track(track_request('bars' => bars, 'bpm' => bpm, 'timeSig' => sig))
      assert track.valid?, "#{bars} bars at #{bpm} in #{sig}: #{track.errors.full_messages.inspect}"
    end

    # A bad bpm is refused for the bpm alone.
    track = build_track(track_request('bars' => 32, 'bpm' => 30))
    refute track.valid?
    assert_empty track.errors[:bars]
  end

  test 'limits describe the length rule for clients' do
    assert_equal({ maxSeconds: 120.0, spareBars: 4, bars: [8, 16, 32], bpmRange: [40, 240],
                   timeSignatures: %w[2/4 3/4 4/4 6/8] }, Spree::UserTrack.limits)
  end

  test 'title names the style and key' do
    track = build_track(track_request('key' => 6, 'scale' => 'major'))
    assert_equal 'Chillhop in F# major', track.default_title
  end

  test 'webhook token finds the track, compared in constant time' do
    track = create_user_track(@user)
    assert_match(/\A#{track.id}-[A-Za-z0-9_-]{40,}\z/, track.webhook_token)
    assert_equal track, Spree::UserTrack.find_by_webhook_token(track.webhook_token)
    assert_nil Spree::UserTrack.find_by_webhook_token("#{track.id}-wrong")
    assert_nil Spree::UserTrack.find_by_webhook_token('nope')
    assert_nil Spree::UserTrack.find_by_webhook_token(nil)
    other = create_user_track(@user)
    assert_nil Spree::UserTrack.find_by_webhook_token("#{other.id}-#{track.webhook_secret}")
  end
end
