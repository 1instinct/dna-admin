require 'test_helper'

class UserTracks::PromptTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  def track(request = {})
    Spree::UserTrack.new(user: @user, request: track_request(request))
  end

  test 'builds the generator input with exactly the agreed keys' do
    input = UserTracks::Prompt.build(track, seed: 1234)
    assert_equal %i[prompt lyrics duration thinking bpm key_scale time_signature seed].sort, input.keys.sort
    assert_equal '[Instrumental]', input[:lyrics]
    assert_equal false, input[:thinking]
    assert_equal 100, input[:bpm]
    assert_equal 'A Minor', input[:key_scale]
    assert_equal '4', input[:time_signature]
    assert_equal 1234, input[:seed]
  end

  test 'duration is (bars + 4) bars of time, capped at 120 s' do
    assert_equal 48.0, UserTracks::Prompt.build(track('bars' => 16, 'bpm' => 100))[:duration]
    assert_equal 120.0, UserTracks::Prompt.build(track('bars' => 32, 'bpm' => 60))[:duration]
    # 3/4 at 90: 12 bars of 3 beats.
    assert_equal 24.0, UserTracks::Prompt.build(track('bars' => 8, 'bpm' => 90, 'timeSig' => '3/4'))[:duration]
    assert_equal '3', UserTracks::Prompt.build(track('timeSig' => '3/4'))[:time_signature]
    assert_equal '6', UserTracks::Prompt.build(track('timeSig' => '6/8'))[:time_signature]
  end

  test 'the prompt is the caption, the mood words and the loop guidance' do
    prompt = UserTracks::Prompt.build(track('moods' => %w[warm dark]))[:prompt]
    assert prompt.start_with?('chillhop beat, dusty boom bap drums, warm electric piano chords, round bass, warm, mellow, dark, brooding, ')
    assert prompt.end_with?(UserTracks::Prompt::LOOP_GUIDANCE)
    assert_includes UserTracks::Prompt::LOOP_GUIDANCE, 'no intro, no outro, no fade, no vocals'
  end

  test 'the prompt stays within the generator limit, keeping the loop guidance' do
    UserTracks.config.styles_path = write_styles('caption' => 'very long caption ' * 60)
    prompt = UserTracks::Prompt.build(track('moods' => []))[:prompt]
    assert prompt.length <= UserTracks::Prompt::MAX_PROMPT
    assert prompt.end_with?(UserTracks::Prompt::LOOP_GUIDANCE)
  end

  test 'a fresh seed each time unless one is given' do
    seeds = Array.new(5) { UserTracks::Prompt.build(track)[:seed] }
    assert seeds.all? { |s| s.is_a?(Integer) && s >= 0 && s < 2**31 }
    assert seeds.uniq.size > 1
  end

  test 'cost estimate is the requested seconds at the per-second price' do
    assert_in_delta 48.0 * 0.0003, UserTracks::Prompt.cost_estimate(track('bars' => 16, 'bpm' => 100)), 1e-9
  end

  private

  def write_styles(overrides)
    file = Tempfile.new(['styles', '.yml'])
    style = { 'id' => 'chillhop', 'label' => 'Chillhop', 'bpmRange' => [80, 96] }.merge(overrides)
    file.write({ 'moods' => [{ 'id' => 'warm' }], 'styles' => [style] }.to_yaml)
    file.close
    @tempfiles = (@tempfiles || []) << file
    file.path
  end
end
