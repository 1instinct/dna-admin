module Spree
  # A user's public identity: handle, name, photo, bio, website and links. The row is created on
  # the user's first save; without a handle there is no public profile.
  class UserProfile < Spree::Base
    self.table_name = 'spree_user_profiles'

    VISIBILITIES = %w[public private].freeze
    NAME_MAX = 40
    BIO_MAX = 280
    WEBSITE_MAX = 200
    LINK_VALUE_MAX = 100

    HANDLE_MESSAGES = {
      invalid: "must be 3-30 lowercase letters, numbers or underscores, not only numbers, with no leading, trailing or double underscores",
      reserved: 'is reserved',
      not_allowed: "isn't allowed",
      taken: 'is taken'
    }.freeze

    belongs_to :user, class_name: 'Spree::User', inverse_of: :profile
    has_one_attached :avatar

    before_validation :normalize_fields
    before_save :track_handle_change

    validates :user_id, uniqueness: true
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :name, length: { maximum: NAME_MAX }
    validates :bio, length: { maximum: BIO_MAX }
    validate :validate_no_null_bytes
    validate :validate_handle
    validate :validate_words
    validate :validate_website
    validate :validate_links
    validate :validate_avatar

    scope :with_handle, -> { where.not(handle: nil) }
    # Profiles anyone may see: not hidden by moderation, owner neither deleted nor locked.
    scope :visible, lambda {
      with_handle.where(hidden_at: nil)
                 .joins(:user).where(Spree::User.table_name => { deleted_at: nil, locked_at: nil })
    }

    # Blank or NUL-bearing input matches nothing (Postgres can't take NUL in a query).
    scope :by_handle, lambda { |handle|
      normalized = Profiles::HandlePolicy.normalize(handle)
      normalized.empty? || normalized.include?("\0") ? none : where('lower(handle) = ?', normalized)
    }

    def self.find_by_handle(handle)
      by_handle(handle).first
    end

    def public_visibility?
      visibility == 'public'
    end

    def hidden?
      hidden_at.present?
    end

    # When the handle may change again (nil: now).
    def handle_changeable_at(now = Time.current)
      return unless handle_changed_at

      at = handle_changed_at + Profiles.config.handle_cooldown
      at > now ? at : nil
    end

    # Only the configured variants are ever served; the stored image is already a server-side
    # re-encode (see Profiles::AvatarUpload).
    def avatar_variant(size)
      transformations = Profiles.config.avatar_variants[size.to_sym]
      return unless transformations && avatar.attached?

      avatar.variant(transformations)
    end

    private

    def normalize_fields
      self.handle = handle.nil? ? nil : Profiles::HandlePolicy.normalize(handle).presence
      self.name = name.to_s.strip.presence
      self.bio = bio.to_s.strip.presence
      self.website = website.to_s.strip.presence
      self.links = {} if links.blank?
      self.visibility = visibility.to_s.strip.downcase.presence || 'public'
    end

    def validate_no_null_bytes
      %i[name bio website].each do |field|
        errors.add(field, 'contains invalid characters') if public_send(field).to_s.include?("\0")
      end
    end

    def validate_handle
      if handle.nil?
        errors.add(:handle, "can't be removed once set") if handle_in_database.present?
        return
      end
      return unless new_record? || will_save_change_to_handle?

      result = Profiles::HandlePolicy.check(handle, user: user, profile: self)
      case result
      when :ok then nil
      when :cooldown
        errors.add(:handle, "can only be changed once every #{Profiles.config.handle_cooldown.inspect}")
      else
        errors.add(:handle, HANDLE_MESSAGES.fetch(result))
      end
    end

    def validate_words
      errors.add(:name, "isn't allowed") unless Profiles::ContentFilter.allowed?(name, mode: :words)
      errors.add(:bio, "isn't allowed") unless Profiles::ContentFilter.allowed?(bio, mode: :words)
    end

    def validate_website
      return if website.nil?

      if website.length > WEBSITE_MAX
        errors.add(:website, "is too long (maximum is #{WEBSITE_MAX} characters)")
        return
      end
      uri = URI.parse(website)
      ok = %w[http https].include?(uri.scheme&.downcase) && uri.host.present? && !website.match?(/\s/)
      errors.add(:website, 'must be an http or https link') unless ok
    rescue URI::InvalidURIError
      errors.add(:website, 'must be an http or https link')
    end

    def validate_links
      unless links.is_a?(Hash)
        errors.add(:links, 'must be an object')
        return
      end
      unknown = links.keys.map(&:to_s) - Profiles.config.links_keys
      errors.add(:links, "has unknown keys: #{unknown.join(', ')}") if unknown.any?
      bad = links.values.reject { |v| v.is_a?(String) && v.length <= LINK_VALUE_MAX && !v.include?("\0") }
      errors.add(:links, "values must be text of at most #{LINK_VALUE_MAX} characters") if bad.any?
    end

    def validate_avatar
      return unless avatar.attached?

      blob = avatar.blob
      errors.add(:avatar, 'must be a JPEG, PNG or WebP image') unless Profiles.config.avatar_content_types.include?(blob.content_type)
      errors.add(:avatar, "must be at most #{Profiles.config.avatar_max_bytes / 1.megabyte} MB") if blob.byte_size > Profiles.config.avatar_max_bytes
    end

    # First set is free; later changes start the cooldown.
    def track_handle_change
      return unless will_save_change_to_handle?

      self.handle_changed_at = Time.current if handle_in_database.present?
    end
  end
end
