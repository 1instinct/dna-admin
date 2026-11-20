require 'open3'
require 'json'

module UserTracks
  # Runs lib/user_tracks/track_post.py on a generated file: it cuts a seamless whole-bar loop to
  # out_path and measures it, printing one JSON object (contract: lib/user_tracks/README.md and the
  # spec's "track_post.py contract"):
  #
  #   python3 track_post.py --in in.flac --out loop.flac --bpm 100 --bars 16 --beats-per-bar 4
  #                         --key A --scale minor
  #
  # UserTracks::Post.runner takes the argv and answers the script's stdout; tests replace it. The
  # default runs the command with UserTracks.config.post_timeout and raises Post::Error on a
  # non-zero exit (a crash: an unusable track is `ok: false` with exit 0) or a timeout.
  #
  # One run at a time per process (LOCK): the script's memory is what limits a dyno, so a second
  # finalise waits for the first run to end.
  module Post
    class Error < StandardError; end

    LOCK = Mutex.new

    DEFAULT_RUNNER = ->(argv) { UserTracks::Post.run(argv, UserTracks.config.post_timeout) }

    class << self
      attr_writer :runner

      def runner
        @runner || DEFAULT_RUNNER
      end

      # The parsed result, a Hash with string keys. Raises Error when the output isn't one JSON
      # object, or says ok without writing the loop.
      def call(in_path:, out_path:, track:)
        command = argv(in_path, out_path, track)
        result = parse(LOCK.synchronize { runner.call(command) })
        raise Error, 'track_post said ok but wrote no loop' if result['ok'] && !File.size?(out_path)

        result
      end

      def argv(in_path, out_path, track)
        [UserTracks.config.python.to_s, UserTracks.config.script_path.to_s,
         '--in', in_path.to_s, '--out', out_path.to_s,
         '--bpm', track.bpm.to_s, '--bars', track.bars.to_s, '--beats-per-bar', track.beats_per_bar.to_s,
         '--key', UserTracks::Keys.name(track.key_pc), '--scale', track.scale]
      end

      def parse(stdout)
        text = stdout.to_s.strip
        candidates = [text, text.lines.map(&:strip).reverse.find { |line| line.start_with?('{') }].compact
        candidates.each do |candidate|
          parsed = JSON.parse(candidate)
          return parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError
          next
        end
        raise Error, 'track_post printed no JSON object'
      end

      # Runs argv, killing it after `timeout` seconds; answers stdout.
      def run(argv, timeout)
        Open3.popen3(*argv) do |stdin, stdout, stderr, wait|
          stdin.close
          out = Thread.new { stdout.read }
          err = Thread.new { stderr.read }
          unless wait.join(timeout)
            kill(wait.pid)
            wait.join
            raise Error, "track_post timed out after #{timeout} s"
          end
          status = wait.value
          unless status.success?
            Rails.logger.error("[user_tracks] track_post exited #{status.exitstatus}: #{err.value.to_s[-500..] || err.value}")
            raise Error, "track_post exited #{status.exitstatus}"
          end
          out.value
        end
      rescue SystemCallError => e
        raise Error, "track_post could not run (#{e.class})"
      end

      def kill(pid)
        Process.kill('KILL', pid)
      rescue SystemCallError
        nil
      end
    end
  end
end
