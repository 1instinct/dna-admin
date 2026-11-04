Rails.application.config.active_storage.service = :amazon

# Enable proxy mode for stable, cacheable URLs (no expiring S3 signatures)
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy
