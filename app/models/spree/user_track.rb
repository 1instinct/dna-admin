module Spree
  # A backing track a user asked a generator for (AI backing tracks; see app/services/user_tracks.rb).
  # Private to its maker. Soft-deleted (deleted_at): a deleted track keeps its row so the quota,
  # the hourly limit and the spend breaker still count it, and its audio is purged.
  #
  # request     as asked: { style, moods, bars, bpm, key (0 C ... 11 B), scale, timeSig }
  # generation  { provider, model, seeds[], requestIds[], requestId (current), attempts, costUsd,
  #               durationSec, analysis[] (raw post-processing JSON per attempt), candidate, failure }
  # profile     once ready: { bpm, key, scale, lowNote, medianNote, highNote, timbre,
  #               profileSource: { bpm, key }, keyConfidence, keyNote }
  # loop_info   once ready: { sampleRate, loopSamples }
  # audio       the loop (FLAC), on Active Storage
  class UserTrack < Spree::Base
    self.table_name = 'spree_user_tracks'

    STATUSES = %w[queued generating finalizing ready failed].freeze
    IN_FLIGHT = %w[queued generating finalizing].freeze
    SOURCES = %w[ai].freeze
    BARS = [8, 16, 32].freeze
    BPM_RANGE = (40..240).freeze
    TIME_SIGNATURES = %w[2/4 3/4 4/4 6/8].freeze
    MOODS_MAX = 2
    REQUEST_FIELDS = %w[style moods bars bpm key scale timeSig].freeze

    enum status: STATUSES.index_with(&:itself)

    belongs_to :user, class_name: 'Spree::User'
    has_one_attached :audio

    before_validation :assign_webhook_secret, on: :create

    validates :source, inclusion: { in: SOURCES }
    validates :webhook_secret, presence: true
    validate :request_is_valid

    scope :kept, -> { where(deleted_at: nil) }
    scope :in_flight, -> { where(status: IN_FLIGHT) }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    # The request as the API takes it (string or symbol keys, strings or numbers), with types
    # normalised: bars, bpm (rounded) and key as integers, the scale lowercased, timeSig "N/D".
    # Values that can't be read are kept as they are, for validation to refuse. Missing moods take
    # the style's defaults, a missing bpm the middle of the style's range, a missing timeSig 4/4.
    def self.normalize_request(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      raw = (raw || {}).to_h.stringify_keys
      style = raw['style'].to_s.strip.presence
      known = UserTracks::Styles.find(style)
      {
        'style' => style,
        'moods' => normalize_moods(raw['moods'], known),
        'bars' => integer(raw['bars']),
        'bpm' => raw['bpm'].nil? && known ? known[:bpmRange].sum / 2 : rounded(raw['bpm']),
        'key' => normalize_key(raw['key']),
        'scale' => raw['scale'].is_a?(String) ? raw['scale'].strip.downcase : raw['scale'],
        'timeSig' => normalize_time_signature(raw.key?('timeSig') ? raw['timeSig'] : raw['time_sig'])
      }
    end

    def self.normalize_moods(value, style)
      return (style ? style[:defaultMoods].dup : []) if value.nil?
      return value.split(',').map(&:strip).reject(&:empty?).uniq if value.is_a?(String)
      return value.map(&:to_s).uniq if value.is_a?(Array)

      value
    end

    def self.normalize_key(value)
      pc = UserTracks::Keys.pc(value)
      pc.nil? ? value : pc
    end

    def self.normalize_time_signature(value)
      return '4/4' if value.nil?

      text = value.to_s.strip
      return text if text.include?('/')

      { '2' => '2/4', '3' => '3/4', '4' => '4/4', '6' => '6/8' }.fetch(text, text)
    end

    def self.integer(value)
      return value if value.is_a?(Integer)
      return value.to_i if value.is_a?(Float) && value == value.round
      return Integer(value.strip, 10) if value.is_a?(String) && value.strip.match?(/\A\d+\z/)

      value
    end

    def self.rounded(value)
      number = value.is_a?(Numeric) ? value : Float(value.to_s, exception: false)
      number && number.finite? ? number.round : value
    end

    # "<id>-<secret>", the last part of the provider webhook URL.
    def webhook_token
      "#{id}-#{webhook_secret}"
    end

    # Where the provider calls back when a generation finishes, or nil without
    # USER_TRACKS_WEBHOOK_HOST (the track then finishes through reconcile).
    def webhook_url
      host = UserTracks.config.webhook_host
      "#{host}/api/v1/user_tracks/webhook/#{webhook_token}" if host
    end

    # The track a webhook token names, or nil; the secret is compared in constant time.
    def self.find_by_webhook_token(token)
      id, secret = token.to_s.split('-', 2)
      return unless id.to_s.match?(/\A\d+\z/) && secret.present?

      track = find_by(id: id.to_i)
      track if track && ActiveSupport::SecurityUtils.secure_compare(track.webhook_secret.to_s, secret)
    end

    def style
      UserTracks::Styles.find(request['style'])
    end

    def bars
      request['bars'].to_i
    end

    def bpm
      request['bpm'].to_i
    end

    def key_pc
      request['key'].to_i
    end

    def scale
      request['scale'].to_s
    end

    def time_signature
      request['timeSig'].presence || '4/4'
    end

    def beats_per_bar
      time_signature.split('/').first.to_i
    end

    # "Chillhop in A minor".
    def default_title(key: key_pc, scale: self.scale)
      label = style&.dig(:label) || request['style'].to_s.titleize
      "#{label} in #{UserTracks::Keys.label(key, scale)}"
    end

    private

    def assign_webhook_secret
      self.webhook_secret ||= SecureRandom.urlsafe_base64(32)
    end

    def request_is_valid
      r = request.is_a?(Hash) ? request : {}
      errors.add(:style, 'is not a known style') unless UserTracks::Styles.find(r['style'])
      validate_moods(r['moods'])
      errors.add(:bars, "must be one of #{BARS.join(', ')}") unless BARS.include?(r['bars'])
      unless r['bpm'].is_a?(Integer) && BPM_RANGE.cover?(r['bpm'])
        errors.add(:bpm, "must be a number from #{BPM_RANGE.min} to #{BPM_RANGE.max}")
      end
      errors.add(:key, 'must be a pitch class from 0 (C) to 11 (B)') unless r['key'].is_a?(Integer) && (0..11).cover?(r['key'])
      errors.add(:scale, 'must be major or minor') unless UserTracks::Keys::SCALES.include?(r['scale'])
      errors.add(:timeSig, "must be one of #{TIME_SIGNATURES.join(', ')}") unless TIME_SIGNATURES.include?(r['timeSig'])
    end

    def validate_moods(moods)
      unless moods.is_a?(Array) && moods.all? { |m| m.is_a?(String) }
        errors.add(:moods, 'must be a list of mood ids')
        return
      end
      errors.add(:moods, "must be at most #{MOODS_MAX}") if moods.size > MOODS_MAX
      unknown = moods.reject { |m| UserTracks::Styles.find_mood(m) }
      errors.add(:moods, "has unknown moods: #{unknown.join(', ')}") if unknown.any?
    end
  end
end
