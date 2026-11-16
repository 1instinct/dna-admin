module UserTracks
  # What to do with a finished attempt, from its track_post analysis (spec "Decide"):
  #
  #   UserTracks::Decide.call(track, analysis)
  #   # => Result(action: :ready | :regenerate | :fail, use:, profile:, keep_candidate:, reason:)
  #
  # - No loop window (ok false) or no tempo match (bpmMatch null): regenerate once, then fail.
  # - Key measured as asked: ready.
  # - Key measured confidently (score >= 0.75 and margin >= 0.15) but different (a relative major
  #   or minor counts as different): regenerate once, keeping this loop as the candidate; if the
  #   second attempt misses too, ready with the better-scoring of the two, in its measured key,
  #   with keyNote "Came out in F major".
  # - Key not confident: ready, labelled with the requested key (profileSource.key "requested").
  # At most one regeneration per track. When the second attempt is unusable but the first was kept
  # (a confident key miss), that one is used.
  #
  # use is :current (this attempt's loop) or :candidate (the kept loop, already attached).
  module Decide
    Result = Struct.new(:action, :use, :profile, :keep_candidate, :reason, keyword_init: true)

    CONFIDENT_SCORE = 0.75
    CONFIDENT_MARGIN = 0.15
    MAX_ATTEMPTS = 2

    module_function

    def call(track, analysis)
      attempt = track.generation['attempts'].to_i
      retry_left = attempt < MAX_ATTEMPTS
      candidate = track.generation.dig('candidate', 'analysis')

      problem = unusable(analysis)
      if problem
        return Result.new(action: :regenerate, reason: problem, keep_candidate: false) if retry_left
        return ready_with_candidate(track, candidate, analysis) if candidate

        return Result.new(action: :fail, reason: problem)
      end

      measured = measured_key(analysis)
      if measured == [track.key_pc, track.scale]
        return ready(:current, profile(track, analysis, measured, 'measured'))
      end
      return ready(:current, profile(track, analysis, [track.key_pc, track.scale], 'requested')) unless measured && confident?(analysis)
      return Result.new(action: :regenerate, reason: 'key_miss', keep_candidate: true) if retry_left

      if candidate && score(candidate) > score(analysis)
        ready_with_candidate(track, candidate, analysis)
      else
        ready(:current, profile(track, analysis, measured, 'measured', note: true))
      end
    end

    # 'no_loop_window', 'tempo_drift' or nil.
    def unusable(analysis)
      return 'no_loop_window' unless analysis['ok']
      return 'tempo_drift' if analysis['bpmMatch'].blank?

      nil
    end

    def ready_with_candidate(track, candidate, _current)
      measured = measured_key(candidate)
      ready(:candidate, profile(track, candidate, measured, 'measured', note: measured != [track.key_pc, track.scale]))
    end

    def ready(use, profile)
      Result.new(action: :ready, use: use, profile: profile)
    end

    # [pitch class, scale] or nil.
    def measured_key(analysis)
      pc = analysis['keyPc'].is_a?(Integer) ? analysis['keyPc'] : UserTracks::Keys.pc(analysis['key'].to_s)
      scale = analysis['scale'].to_s.downcase
      return unless pc.is_a?(Integer) && (0..11).cover?(pc) && UserTracks::Keys::SCALES.include?(scale)

      [pc, scale]
    end

    def confident?(analysis)
      score(analysis) >= CONFIDENT_SCORE && analysis['keyMargin'].to_f >= CONFIDENT_MARGIN
    end

    def score(analysis)
      analysis['keyScore'].to_f
    end

    # The stored profile: a TrackProfile (bpm, key, scale, lowNote, medianNote, highNote, timbre)
    # plus profileSource, keyConfidence and keyNote. bpm is the requested tempo, which the loop is
    # cut to and was checked against ("checked").
    def profile(track, analysis, key, key_source, note: false)
      {
        'bpm' => track.bpm,
        'key' => key[0],
        'scale' => key[1],
        'lowNote' => midi(analysis['lowNote']),
        'medianNote' => midi(analysis['medianNote']),
        'highNote' => midi(analysis['highNote']),
        'timbre' => analysis['timbre'].is_a?(Hash) ? analysis['timbre'] : nil,
        'profileSource' => { 'bpm' => 'checked', 'key' => key_source },
        'keyConfidence' => analysis['keyScore'].is_a?(Numeric) ? analysis['keyScore'].round(3) : nil,
        'keyNote' => note ? "Came out in #{UserTracks::Keys.label(key[0], key[1])}" : nil
      }
    end

    def midi(value)
      value.is_a?(Numeric) && value.between?(0, 127) ? value : nil
    end
  end
end
