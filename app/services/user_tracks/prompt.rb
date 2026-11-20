module UserTracks
  # The generator input for a track (fal-ai/ace-step-1.5):
  #   { prompt, lyrics: "[Instrumental]", duration, thinking: false, bpm, key_scale: "A Minor",
  #     time_signature: "4", seed }
  # The prompt is the style's caption, the mood words and the fixed loop guidance. The duration is
  # (bars + 4) bars at the track's tempo, capped at UserTracks.config.max_duration: the 4 spare bars
  # let the loop be cut clear of the generator's intro and its trailing silence.
  module Prompt
    LOOP_GUIDANCE = 'instrumental backing track, steady groove from the first beat, no intro, no outro, ' \
                    'no fade, no vocals, consistent arrangement, leaves room for a lead'.freeze
    LYRICS = '[Instrumental]'.freeze
    SPARE_BARS = 4
    # The generator's prompt limit, in characters.
    MAX_PROMPT = 512

    module_function

    def build(track, seed: new_seed)
      {
        prompt: prompt(track),
        lyrics: LYRICS,
        duration: duration(track),
        thinking: false,
        bpm: track.bpm,
        key_scale: UserTracks::Keys.key_scale(track.key_pc, track.scale),
        time_signature: track.beats_per_bar.to_s,
        seed: seed
      }
    end

    def duration(track)
      seconds = (track.bars + SPARE_BARS) * track.beats_per_bar * 60.0 / track.bpm
      [seconds, UserTracks.config.max_duration.to_f].min.round(2)
    end

    def cost_estimate(track)
      (duration(track) * UserTracks.config.price_per_second).round(6)
    end

    # The caption and mood words are cut (at a comma where possible) to keep the loop guidance whole.
    def prompt(track)
      words = track.request['moods'].to_a.filter_map { |id| UserTracks::Styles.find_mood(id)&.dig(:words) }
      lead = [track.style&.dig(:caption), *words].compact.map(&:strip).reject(&:empty?).join(', ')
      room = MAX_PROMPT - LOOP_GUIDANCE.length - 2
      lead = cut(lead, room) if lead.length > room
      [lead.presence, LOOP_GUIDANCE].compact.join(', ')
    end

    def cut(text, room)
      head = text[0, room]
      comma = head.rindex(',')
      (comma && comma > room / 2 ? head[0, comma] : head).strip
    end

    # 0 ... 2^31 - 1: fits the generator's integer seed.
    def new_seed
      SecureRandom.random_number(2**31)
    end
  end
end
