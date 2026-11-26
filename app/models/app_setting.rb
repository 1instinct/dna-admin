# Force-upgrade gate for the mobile app: users below `version` are blocked. The app's bundle id
# comes from APP_BUNDLE_ID.
class AppSetting < ApplicationRecord
  DEFAULT_NAME = (ENV['APP_BUNDLE_ID'].presence || 'com.example.app').freeze
  BOTH = 'ios-android'.freeze
  PLATFORMS = [BOTH, 'ios', 'android'].freeze
  # Platforms an app can ask for; 'ios-android' records apply to both.
  CLIENT_PLATFORMS = %w[ios android].freeze
  GATE_OFF = '0.0.0'.freeze

  attribute :name, :string, default: -> { DEFAULT_NAME }

  # Admin override: save an iOS minimum the App Store doesn't serve yet.
  attribute :allow_ahead_of_store, :boolean, default: false

  validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be semantic (e.g. 1.2.3)' }
  validates :platform, inclusion: { in: PLATFORMS, message: "must be one of #{PLATFORMS.join(', ')}" }
  validate :live_in_app_store, on: :create

  # Platform-blind gate, for app builds that don't send a platform.
  def self.latest
    order(:updated_at).last || new(name: DEFAULT_NAME, platform: BOTH, version: GATE_OFF)
  end

  # Gate for one platform: the newest record for that platform or for both.
  # An unknown or blank platform falls back to `latest`.
  def self.latest_for(platform)
    platform = platform.to_s.strip.downcase
    return latest unless CLIENT_PLATFORMS.include?(platform)

    where(platform: [platform, BOTH]).order(:updated_at, :id).last ||
      new(name: DEFAULT_NAME, platform: platform, version: GATE_OFF)
  end

  def gate_off?
    Gem::Version.new(version) <= Gem::Version.new(GATE_OFF)
  rescue ArgumentError
    false
  end

  private

  # A minimum above what the App Store serves would block every iOS user with nothing to
  # update to. Google Play has no public lookup, so Android minimums aren't checked.
  def live_in_app_store
    return if allow_ahead_of_store
    return unless [BOTH, 'ios'].include?(platform)
    return if errors.include?(:version) || version.blank? || gate_off?

    live = begin
      AppStoreLookup.live_version(name.presence || DEFAULT_NAME)
    rescue AppStoreLookup::Error => e
      Rails.logger.warn("[AppSetting] App Store lookup failed: #{e.message}")
      return refuse_ahead_of_store('lookup failed')
    end
    return refuse_ahead_of_store('not found') if live.blank?

    live_version = begin
      Gem::Version.new(live)
    rescue ArgumentError
      return refuse_ahead_of_store(live)
    end
    refuse_ahead_of_store(live) if live_version < Gem::Version.new(version)
  end

  def refuse_ahead_of_store(live)
    errors.add(:base, "Version #{version} isn't live in the App Store yet (live: #{live}). " \
                      'Users below it would be blocked with nothing to update to. ' \
                      "Tick 'Allow ahead of the App Store' to save anyway.")
  end
end
