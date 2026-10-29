# Warn at boot (setting names only, never values) when in-app purchase
# verification is only partly configured.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  missing = Iap::Configuration.from_env.missing_settings
  if missing.any?
    Rails.logger.warn("[iap] in-app purchase verification is incomplete; missing settings: #{missing.join(', ')}")
  end
end
