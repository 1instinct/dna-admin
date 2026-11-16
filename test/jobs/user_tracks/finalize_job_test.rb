require 'test_helper'

class UserTracks::FinalizeJobTest < ActiveJob::TestCase
  setup do
    setup_user_tracks
    @user = create(:user)
    @track = generating_track(@user)
  end

  teardown { reset_user_tracks! }

  def audio_attachments(track)
    ActiveStorage::Attachment.where(record_type: 'Spree::UserTrack', record_id: track.id, name: 'audio')
  end

  test 'fetches the result from fal, cuts and checks the loop, stores it and marks the track ready' do
    stub_fal_done
    calls = stub_post_runner(track_analysis)

    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'ready', @track.status
    assert @track.ready_at
    assert_equal 'Chillhop in A minor', @track.title
    assert_equal({ 'sampleRate' => 48_000, 'loopSamples' => 1_843_200 }, @track.loop_info)
    assert_equal 9, @track.profile['key']
    assert_equal 'measured', @track.profile['profileSource']['key']
    assert @track.audio.attached?
    assert_equal 'audio/flac', @track.audio.blob.content_type
    assert_equal 'fLaC-loop-1', @track.audio.download
    assert_equal [track_analysis.merge('attempt' => 1)], @track.generation['analysis']
    assert_nil @track.credit_refunded_at
    assert_equal 1, calls.size
  end

  test 'a loop cut at the measured beat period stores loopBpm as the profile bpm; the request keeps the asked bpm' do
    stub_fal_done
    stub_post_runner(track_analysis('loopBpm' => 100.42, 'loopSamples' => 1_835_515))
    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'ready', @track.status
    assert_equal 100.42, @track.profile['bpm']
    assert_equal 'measured', @track.profile['profileSource']['bpm']
    assert_equal 100, @track.request['bpm']
    assert_equal 1_835_515, @track.loop_info['loopSamples']
    get_json = UserTracks::Presenter.call(@track)
    assert_equal 100.42, get_json[:profile]['bpm']
    assert_equal 100, get_json[:request]['bpm']
  end

  test 'the downloaded file is what the script reads' do
    stub_fal_done
    seen = nil
    stub_post_runner(lambda { |argv|
      seen = File.binread(argv[argv.index('--in') + 1])
      track_analysis
    })
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_equal 'fLaC-raw-req-1', seen
  end

  test 'a track still running at fal goes back to generating' do
    stub_fal_status('req-1', 'IN_PROGRESS')
    stub_post_runner(track_analysis)
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_equal 'generating', @track.reload.status
    assert_not_requested :get, "#{FAL_QUEUE}/requests/req-1"
  end

  test 'a failed generation fails the track and refunds the credit' do
    stub_fal_status('req-1', 'COMPLETED', error: 'out of memory')
    UserTracks::FinalizeJob.perform_now(@track.id)
    @track.reload
    assert_equal 'failed', @track.status
    assert @track.credit_refunded_at
    assert_equal 'provider_failed', @track.generation['failure']
  end

  test 'fal unreachable leaves the track generating for reconcile' do
    stub_request(:get, "#{FAL_QUEUE}/requests/req-1/status").to_return(status: 502)
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_equal 'generating', @track.reload.status
    assert_nil @track.credit_refunded_at
  end

  test 'a script crash fails the track with a refund' do
    stub_fal_done
    UserTracks::Post.runner = ->(_argv) { raise UserTracks::Post::Error, 'track_post exited 1' }
    UserTracks::FinalizeJob.perform_now(@track.id)
    @track.reload
    assert_equal 'failed', @track.status
    assert_equal 'analysis_failed', @track.generation['failure']
    assert @track.credit_refunded_at
  end

  test 'a confident key miss regenerates once with a new seed, keeping the first loop' do
    stub_fal_done('req-1')
    f_major = track_analysis('key' => 'F', 'keyPc' => 5, 'scale' => 'major', 'keyScore' => 0.9, 'keyMargin' => 0.3)
    stub_post_runner(f_major)

    UserTracks::FinalizeJob.perform_now(@track.id)
    @track.reload
    assert_equal 'queued', @track.status
    assert_enqueued_with(job: UserTracks::SubmitJob, args: [@track.id])
    assert_equal 'fLaC-loop-1', @track.audio.download
    assert_equal 1, @track.generation['candidate']['attempt']

    # The second attempt also misses, scoring lower: the first is kept, with its key.
    stub_request(:post, FAL_QUEUE).with(query: hash_including({})).to_return(status: 200, body: { request_id: 'req-2' }.to_json)
    UserTracks::SubmitJob.perform_now(@track.id)
    assert_equal 'generating', @track.reload.status
    stub_fal_done('req-2')
    stub_post_runner(track_analysis('key' => 'D', 'keyPc' => 2, 'scale' => 'minor', 'keyScore' => 0.8, 'keyMargin' => 0.2))
    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'ready', @track.status
    assert_equal 'Came out in F major', @track.profile['keyNote']
    assert_equal 'Chillhop in F major', @track.title
    assert_equal 'fLaC-loop-1', @track.audio.download
    assert_equal 1, audio_attachments(@track).count
    assert_equal 1, ActiveStorage::Blob.count
    assert_equal 2, @track.generation['seeds'].size
    assert_equal [1, 2], @track.generation['analysis'].map { |a| a['attempt'] }
    assert_nil @track.credit_refunded_at
  end

  test 'a second attempt that matches replaces the kept first loop' do
    @track.update_columns(generation: @track.generation.merge('attempts' => 2, 'requestId' => 'req-2',
                                                                'candidate' => { 'attempt' => 1, 'analysis' => track_analysis('keyPc' => 5, 'key' => 'F', 'scale' => 'major') }))
    @track.audio.attach(io: StringIO.new('fLaC-first'), filename: 'loop.flac', content_type: 'audio/flac')
    old_blob = @track.audio.blob
    stub_fal_done('req-2')
    stub_post_runner(track_analysis)
    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'ready', @track.status
    assert_nil @track.profile['keyNote']
    assert_equal 'fLaC-loop-1', @track.audio.download
    refute ActiveStorage::Blob.exists?(old_blob.id)
    assert_nil @track.generation['candidate']
  end

  # Review Focus 3: a mostly silent or very short file.
  test 'no loop window twice: regenerate once, then fail with the credit refunded' do
    stub_fal_done('req-1')
    stub_post_runner(no_window_analysis)
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_equal 'queued', @track.reload.status
    refute @track.audio.attached?

    stub_request(:post, FAL_QUEUE).with(query: hash_including({})).to_return(status: 200, body: { request_id: 'req-2' }.to_json)
    UserTracks::SubmitJob.perform_now(@track.id)
    stub_fal_done('req-2')
    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'failed', @track.status
    assert_equal 'no_loop_window', @track.generation['failure']
    assert @track.credit_refunded_at
    assert_equal 20, UserTracks::Quota.remaining(@user)
    assert_equal 0, ActiveStorage::Blob.count
  end

  test 'tempo drift twice: fail with a refund' do
    @track.update_columns(generation: @track.generation.merge('attempts' => 2))
    stub_fal_done
    stub_post_runner(track_analysis('bpmMatch' => nil))
    UserTracks::FinalizeJob.perform_now(@track.id)
    @track.reload
    assert_equal 'failed', @track.status
    assert_equal 'tempo_drift', @track.generation['failure']
    assert @track.credit_refunded_at
  end

  # Review Focus 1: finalise twice (a double webhook, or reconcile after the webhook).
  test 'finalising twice gives one attachment and one outcome' do
    stub_fal_done
    stub_post_runner(track_analysis)
    UserTracks::FinalizeJob.perform_now(@track.id)
    ready_at = @track.reload.ready_at
    UserTracks::FinalizeJob.perform_now(@track.id)

    @track.reload
    assert_equal 'ready', @track.status
    assert_equal ready_at, @track.ready_at
    assert_equal 1, audio_attachments(@track).count
    assert_equal 1, ActiveStorage::Blob.count
    assert_requested :get, "#{FAL_QUEUE}/requests/req-1", times: 1
  end

  # Review Focus 2: deleted while generating.
  test 'a track deleted while generating is not finalised' do
    UserTracks::Removal.call(@track)
    stub_fal_done
    stub_post_runner(track_analysis)
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_not_requested :get, "#{FAL_QUEUE}/requests/req-1/status"
    assert_equal 0, ActiveStorage::Blob.count
    assert_equal 'generating', @track.reload.status
  end

  test 'a track deleted while finalising leaves no blob behind' do
    stub_fal_done
    stub_post_runner(lambda { |_argv|
      UserTracks::Removal.call(Spree::UserTrack.find(@track.id))
      track_analysis
    })
    UserTracks::FinalizeJob.perform_now(@track.id)
    @track.reload
    assert @track.deleted_at
    refute @track.audio.attached?
    assert_equal 0, ActiveStorage::Blob.count
    assert_equal 0, ActiveStorage::Attachment.count
  end

  test 'a track hard-deleted (account deletion) is a no-op' do
    @track.delete
    UserTracks::FinalizeJob.perform_now(@track.id)
    assert_not_requested :any, /fal/
  end

  test 'the audio URL never reaches the log' do
    url = 'https://v3.fal.media/files/secret-path-xyz/out.flac'
    stub_fal_done('req-1', audio_url: url)
    stub_post_runner(track_analysis)
    log = captured_log { UserTracks::FinalizeJob.perform_now(@track.id) }
    assert_includes log, "track #{@track.id} ready"
    refute_includes log, 'secret-path-xyz'
    refute_includes log, UserTracks.config.fal_key
  end
end
