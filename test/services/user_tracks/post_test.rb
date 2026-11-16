require 'test_helper'

class UserTracks::PostTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks
    @track = Spree::UserTrack.new(user: create(:user), request: track_request('key' => 10, 'timeSig' => '3/4'))
    @dir = Dir.mktmpdir
  end

  teardown do
    reset_user_tracks!
    FileUtils.remove_entry(@dir)
  end

  def run_post
    UserTracks::Post.call(in_path: File.join(@dir, 'in.flac'), out_path: File.join(@dir, 'loop.flac'), track: @track)
  end

  test 'runs the script with the contract arguments and parses its JSON' do
    calls = stub_post_runner(track_analysis)
    assert_equal track_analysis, run_post
    argv = calls.first
    assert_equal [UserTracks.config.python, UserTracks.config.script_path.to_s], argv.first(2)
    assert_equal({ '--in' => File.join(@dir, 'in.flac'), '--out' => File.join(@dir, 'loop.flac'), '--bpm' => '100',
                   '--bars' => '16', '--beats-per-bar' => '3', '--key' => 'Bb', '--scale' => 'minor' },
                 argv.drop(2).each_slice(2).to_h)
  end

  test 'takes the JSON object from the last line when the script prints more' do
    UserTracks::Post.runner = ->(_argv) { "loading...\n#{JSON.generate(no_window_analysis)}\n" }
    assert_equal 'no_loop_window', run_post['reason']
  end

  test 'unreadable output, or ok without a loop file, is an error' do
    UserTracks::Post.runner = ->(_argv) { 'Traceback: boom' }
    assert_raises(UserTracks::Post::Error) { run_post }
    UserTracks::Post.runner = ->(_argv) { '[1, 2]' }
    assert_raises(UserTracks::Post::Error) { run_post }
    UserTracks::Post.runner = ->(_argv) { JSON.generate(track_analysis) }
    assert_raises(UserTracks::Post::Error) { run_post }
  end

  test 'one run at a time per process: a second caller waits for the first' do
    running = 0
    most = 0
    counter = Mutex.new
    UserTracks::Post.runner = lambda do |argv|
      counter.synchronize { most = [most, running += 1].max }
      sleep 0.2
      counter.synchronize { running -= 1 }
      File.binwrite(argv[argv.index('--out') + 1], 'fLaC')
      JSON.generate(track_analysis)
    end

    dirs = Array.new(3) { Dir.mktmpdir }
    threads = dirs.map do |dir|
      Thread.new do
        UserTracks::Post.call(in_path: File.join(dir, 'in.flac'), out_path: File.join(dir, 'loop.flac'), track: @track)
      end
    end
    assert_equal %w[A A A], threads.map { |thread| thread.value['key'] }
    assert_equal 1, most
  ensure
    dirs&.each { |dir| FileUtils.remove_entry(dir) }
  end

  # The production runner, with ruby standing in for python: a script that answers, one that
  # crashes and one that hangs past the timeout.
  test 'the default runner runs the command, and fails on a crash or a timeout' do
    UserTracks::Post.runner = nil
    UserTracks.config.python = RbConfig.ruby
    script = File.join(@dir, 'fake_post.rb')
    File.write(script, <<~RUBY)
      out = ARGV[ARGV.index('--out') + 1]
      File.binwrite(out, 'fLaC')
      warn 'some stderr noise'
      puts '{"ok": true, "key": "Bb", "bpmMatch": "x1"}'
    RUBY
    UserTracks.config.script_path = script
    assert_equal 'Bb', run_post['key']

    File.write(script, "warn 'Traceback'; exit 3\n")
    error = assert_raises(UserTracks::Post::Error) { run_post }
    assert_match(/exited 3/, error.message)

    File.write(script, "sleep 5\n")
    UserTracks.config.post_timeout = 0.5
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(UserTracks::Post::Error) { run_post }
    assert_match(/timed out/, error.message)
    assert Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 4
  end
end
