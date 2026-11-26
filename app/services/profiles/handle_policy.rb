module Profiles
  # Handle rules. A handle is 3-30 of a-z, 0-9 and _, not only digits, with no leading, trailing
  # or double underscore. Input is stripped and lowercased first. Reserved handles and blocked
  # terms come from Profiles.config.
  #
  #   Profiles::HandlePolicy.check(handle, user:)
  #   # => :ok | :invalid | :reserved | :not_allowed | :taken | :cooldown
  #
  # The user's current handle is always :ok. :cooldown means the name is free but the user
  # changed their handle within Profiles.config.handle_cooldown (setting the first one is free).
  #
  # A user holding one of Profiles.config.reserved_handle_roles (default: admin) may take reserved
  # handles and handles starting with a reserved prefix. Every other rule still applies to them:
  # format, blocked terms, taken and the cooldown.
  module HandlePolicy
    FORMAT = /\A[a-z0-9_]{3,30}\z/.freeze

    module_function

    def normalize(handle)
      handle.to_s.strip.downcase
    end

    def valid_format?(handle)
      FORMAT.match?(handle) && !handle.match?(/\A[0-9]+\z/) &&
        !handle.start_with?('_') && !handle.end_with?('_') && !handle.include?('__')
    end

    def check(handle, user:, profile: nil, now: Time.current)
      handle = normalize(handle)
      return :invalid unless valid_format?(handle)

      profile ||= user&.profile
      current = profile&.persisted? ? profile.handle_in_database : nil
      return :ok if current.present? && current == handle

      refused = refusal(handle, allow_reserved: may_take_reserved?(user))
      return refused if refused
      return :taken if taken?(handle, user)
      return :cooldown if current.present? && profile.handle_changeable_at(now)

      :ok
    end

    # What the rules alone say about a normalized handle, without touching the database:
    # :invalid, :reserved, :not_allowed or nil. allow_reserved skips only the reserved check.
    def refusal(handle, allow_reserved: false)
      return :invalid unless valid_format?(handle)
      return :reserved if !allow_reserved && reserved?(handle)
      return :not_allowed unless ContentFilter.allowed?(handle, mode: :handle)

      nil
    end

    def may_take_reserved?(user)
      return false unless user.respond_to?(:has_spree_role?)

      Profiles.config.reserved_handle_roles.any? { |role| user.has_spree_role?(role) }
    end

    def reserved?(handle)
      Profiles.config.reserved_handles.include?(handle) ||
        Profiles.config.reserved_prefixes.any? { |prefix| handle.start_with?(prefix) }
    end

    def taken?(handle, user)
      scope = Spree::UserProfile.where('lower(handle) = ?', handle)
      scope = scope.where.not(user_id: user.id) if user&.id
      scope.exists?
    end
  end
end
