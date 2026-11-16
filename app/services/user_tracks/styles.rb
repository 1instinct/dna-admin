module UserTracks
  # The style and mood vocabulary, from UserTracks.config.styles_path (an app owns its file):
  #
  #   moods:
  #     - { id: warm, label: Warm, words: "warm, mellow" }
  #   styles:
  #     - id: chillhop
  #       label: Chillhop
  #       bpmRange: [80, 96]
  #       defaultMoods: [warm]
  #       caption: chillhop beat, dusty drums, warm electric piano chords, round bass
  #
  # Entries missing an id, a label, a caption or a bpm range inside 40-240 are skipped with a
  # warning. The caption is the generator prompt's opening; mood words follow it.
  module Styles
    BPM_LIMITS = (40..240).freeze

    class << self
      # [{ id:, label:, bpmRange:, defaultMoods:, caption: }]
      def all
        data[:styles]
      end

      def find(id)
        all.find { |style| style[:id] == id.to_s }
      end

      # [{ id:, label:, words: }]
      def moods
        data[:moods]
      end

      def find_mood(id)
        moods.find { |mood| mood[:id] == id.to_s }
      end

      def reset!
        @data = nil
      end

      private

      def data
        @data ||= load(UserTracks.config.styles_path)
      end

      def load(path)
        raw = File.exist?(path) ? YAML.safe_load(File.read(path)) : nil
        raw = {} unless raw.is_a?(Hash)
        moods = Array(raw['moods']).filter_map { |entry| mood(entry) }
        mood_ids = moods.map { |m| m[:id] }
        styles = Array(raw['styles']).filter_map { |entry| style(entry, mood_ids) }
        { styles: styles.freeze, moods: moods.freeze }
      rescue Psych::Exception => e
        Rails.logger.error("[user_tracks] style vocabulary unreadable: #{e.class}")
        { styles: [].freeze, moods: [].freeze }
      end

      def mood(entry)
        return unless entry.is_a?(Hash) && entry['id'].present?

        id = entry['id'].to_s
        { id: id, label: (entry['label'].presence || id.titleize).to_s, words: (entry['words'].presence || id).to_s }.freeze
      end

      def style(entry, mood_ids)
        return skip(entry, 'not a mapping') unless entry.is_a?(Hash)

        id = entry['id'].to_s
        range = Array(entry['bpmRange']).map { |v| Integer(v, exception: false) }
        return skip(id, 'id, label or caption missing') if id.blank? || entry['label'].blank? || entry['caption'].blank?
        unless range.size == 2 && range.all? && range[0] <= range[1] && range.all? { |v| BPM_LIMITS.cover?(v) }
          return skip(id, 'bpmRange must be [low, high] within 40-240')
        end

        defaults = Array(entry['defaultMoods']).map(&:to_s) & mood_ids
        { id: id, label: entry['label'].to_s, bpmRange: range, defaultMoods: defaults.first(2),
          caption: entry['caption'].to_s.squish }.freeze
      end

      def skip(id, why)
        Rails.logger.warn("[user_tracks] style #{id.inspect} skipped: #{why}")
        nil
      end
    end
  end
end
