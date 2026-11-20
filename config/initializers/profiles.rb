# Public profiles, blocks and reports (app/services/profiles.rb holds Profiles.config).
#
# ENV:
#   MODERATION_EMAIL  inbox that receives new content reports (no mail is sent when unset)
#
# Apps add reserved handles or blocked terms with their own config/moderation/<app>_reserved_handles.yml
# or <app>_blocked_terms.yml, or set Profiles.config.extra_reserved_handles in a to_prepare block.
Rails.application.config.to_prepare do
  Spree::User.include(Profiles::UserExtension) unless Spree::User.include?(Profiles::UserExtension)
end
