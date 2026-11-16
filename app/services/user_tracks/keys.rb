module UserTracks
  # Pitch classes (0 C ... 11 B) and their names.
  module Keys
    NAMES = %w[C C# D Eb E F F# G Ab A Bb B].freeze
    SCALES = %w[major minor].freeze
    LETTERS = { 'C' => 0, 'D' => 2, 'E' => 4, 'F' => 5, 'G' => 7, 'A' => 9, 'B' => 11 }.freeze

    module_function

    # A pitch class from 0-11 (or "9"), or a name ("A", "Bb", "f#", "Db"); nil when unreadable.
    # Integers outside 0-11 come back as they are, for validation to refuse.
    def pc(value)
      case value
      when Integer then value
      when Float then value == value.round ? value.to_i : nil
      when String
        text = value.strip
        return Integer(text, 10) if text.match?(/\A-?\d+\z/)

        from_name(text)
      end
    end

    def from_name(text)
      match = text.match(/\A([A-Ga-g])([#b♯♭]?)\z/)
      return unless match

      base = LETTERS.fetch(match[1].upcase)
      shift = { '#' => 1, '♯' => 1, 'b' => -1, '♭' => -1 }.fetch(match[2], 0)
      (base + shift) % 12
    end

    def name(pc)
      NAMES[pc.to_i % 12]
    end

    # "F major", "A minor".
    def label(pc, scale)
      "#{name(pc)} #{scale}"
    end

    # The generator's key_scale: "A Minor".
    def key_scale(pc, scale)
      "#{name(pc)} #{scale.to_s.capitalize}"
    end
  end
end
