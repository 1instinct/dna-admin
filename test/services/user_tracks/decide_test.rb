require 'test_helper'

# UserTracks::Decide: the spec's tempo, key and loop-window rules, from a track_post analysis.
class UserTracks::DecideTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  # A track asked for in A minor at 100 bpm, on attempt `attempts`, with an optional kept candidate.
  def track(attempts: 1, candidate: nil)
    generation = { 'attempts' => attempts }
    generation['candidate'] = { 'attempt' => 1, 'analysis' => candidate } if candidate
    Spree::UserTrack.new(user: @user, request: track_request, generation: generation)
  end

  F_MAJOR = { 'key' => 'F', 'keyPc' => 5, 'scale' => 'major', 'keyScore' => 0.82, 'keyMargin' => 0.2 }.freeze

  test 'key match: ready, key measured' do
    result = UserTracks::Decide.call(track, track_analysis)
    assert_equal :ready, result.action
    assert_equal :current, result.use
    profile = result.profile
    assert_equal 100, profile['bpm']
    assert_equal 9, profile['key']
    assert_equal 'minor', profile['scale']
    assert_equal({ 'bpm' => 'checked', 'key' => 'measured' }, profile['profileSource'])
    assert_equal 0.86, profile['keyConfidence']
    assert_nil profile['keyNote']
    assert_equal [33, 57, 81], profile.values_at('lowNote', 'medianNote', 'highNote')
    assert_equal 60, profile['timbre']['brightness']
  end

  test 'confident other key on the first attempt: regenerate, keeping this loop as a fallback' do
    result = UserTracks::Decide.call(track, track_analysis(F_MAJOR))
    assert_equal :regenerate, result.action
    assert result.keep_candidate
  end

  test 'confident other key on the second attempt: ready in the better-scoring attempt, with a keyNote' do
    # The second attempt scores better: it is kept, with its measured key.
    first = track_analysis('key' => 'D', 'keyPc' => 2, 'scale' => 'minor', 'keyScore' => 0.78, 'keyMargin' => 0.16)
    result = UserTracks::Decide.call(track(attempts: 2, candidate: first), track_analysis(F_MAJOR))
    assert_equal :ready, result.action
    assert_equal :current, result.use
    assert_equal 'Came out in F major', result.profile['keyNote']
    assert_equal [5, 'major'], result.profile.values_at('key', 'scale')
    assert_equal 'measured', result.profile['profileSource']['key']

    # The first scored better: it is kept.
    first = track_analysis(F_MAJOR.merge('keyScore' => 0.9))
    second = track_analysis('key' => 'D', 'keyPc' => 2, 'scale' => 'minor', 'keyScore' => 0.8, 'keyMargin' => 0.2)
    result = UserTracks::Decide.call(track(attempts: 2, candidate: first), second)
    assert_equal :ready, result.action
    assert_equal :candidate, result.use
    assert_equal 'Came out in F major', result.profile['keyNote']
  end

  test 'a relative major or minor is a miss' do
    c_major = track_analysis('key' => 'C', 'keyPc' => 0, 'scale' => 'major')
    assert_equal :regenerate, UserTracks::Decide.call(track, c_major).action
  end

  test 'not confident: ready with the requested key, keySource requested' do
    [{ 'keyScore' => 0.7, 'keyMargin' => 0.3 }, { 'keyScore' => 0.9, 'keyMargin' => 0.1 }].each do |weak|
      result = UserTracks::Decide.call(track, track_analysis(F_MAJOR.merge(weak)))
      assert_equal :ready, result.action
      assert_equal [9, 'minor'], result.profile.values_at('key', 'scale')
      assert_equal 'requested', result.profile['profileSource']['key']
      assert_nil result.profile['keyNote']
    end
    missing = track_analysis('key' => nil, 'keyPc' => nil, 'scale' => nil, 'keyScore' => nil, 'keyMargin' => nil)
    assert_equal 'requested', UserTracks::Decide.call(track, missing).profile['profileSource']['key']
  end

  test 'bpmMatch nil: regenerate, then fail' do
    drift = track_analysis('bpmMatch' => nil)
    result = UserTracks::Decide.call(track, drift)
    assert_equal :regenerate, result.action
    refute result.keep_candidate
    result = UserTracks::Decide.call(track(attempts: 2), drift)
    assert_equal :fail, result.action
    assert_equal 'tempo_drift', result.reason
  end

  test 'x2 and x0.5 tempo matches count' do
    %w[x2 x0.5].each do |match|
      assert_equal :ready, UserTracks::Decide.call(track, track_analysis('bpmMatch' => match)).action
    end
  end

  test 'ok false, no loop window: regenerate, then fail' do
    assert_equal :regenerate, UserTracks::Decide.call(track, no_window_analysis).action
    result = UserTracks::Decide.call(track(attempts: 2), no_window_analysis)
    assert_equal :fail, result.action
    assert_equal 'no_loop_window', result.reason
  end

  test 'a second attempt that is unusable falls back to the kept first one' do
    result = UserTracks::Decide.call(track(attempts: 2, candidate: track_analysis(F_MAJOR)), no_window_analysis)
    assert_equal :ready, result.action
    assert_equal :candidate, result.use
    assert_equal 'Came out in F major', result.profile['keyNote']
  end
end
