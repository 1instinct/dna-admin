module Profiles
  # Moderator actions on profiles and accounts (used by the admin Reports tab and Users page).
  module Moderation
    class Refused < StandardError; end

    module_function

    # A hidden profile 404s publicly; its owner still sees it with hidden: true.
    def hide(profile, reason: nil)
      profile.update_columns(hidden_at: Time.current, hidden_reason: reason.to_s.strip.presence, updated_at: Time.current)
    end

    def unhide(profile)
      profile.update_columns(hidden_at: nil, hidden_reason: nil, updated_at: Time.current)
    end

    def remove_photo(profile)
      profile.avatar.purge_later if profile.avatar.attached?
    end

    def clear_bio(profile)
      profile.update_columns(bio: nil, updated_at: Time.current)
    end

    # Sets Devise's locked_at, revokes OAuth tokens and grants and clears the api key, so the
    # account can neither sign in nor keep using an existing session. Admins can't be locked here.
    def lock(user)
      raise Refused, "Admin accounts can't be locked here." if user.admin?

      now = Time.current
      user.class.transaction do
        user.update_columns(locked_at: now, spree_api_key: nil, updated_at: now)
        [Doorkeeper.config.access_token_model, Doorkeeper.config.access_grant_model].each do |model|
          model.where(resource_owner_id: user.id, revoked_at: nil).update_all(revoked_at: now)
        end
      end
    end

    def unlock(user)
      user.update_columns(locked_at: nil, updated_at: Time.current)
    end
  end
end
