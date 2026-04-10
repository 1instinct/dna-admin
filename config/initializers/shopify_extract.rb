# Shopify extraction tool — development/test only
# Refuses to load in production as a safety guard.

if Rails.env.production?
  Rails.logger.info "ShopifyExtract: not loading in production"
  return
end

require "shopify_extract/config"

Rails.application.config.shopify_extract = nil

if ENV["SHOPIFY_ACCESS_TOKEN"].present?
  Rails.application.config.shopify_extract = ShopifyExtract::Config.new(
    api_base: ENV.fetch("SHOPIFY_API_BASE"),
    access_token: ENV.fetch("SHOPIFY_ACCESS_TOKEN"),
    api_version: ENV.fetch("SHOPIFY_API_VERSION", "2026-01"),
    locales: ENV.fetch("EXTRACT_LOCALES", "en").split(",").map(&:strip),
    output_dir: Rails.root.join(ENV.fetch("EXTRACT_OUTPUT_DIR", "extracted")).to_s,
    max_image_mb: ENV.fetch("EXTRACT_MAX_IMAGE_MB", "500").to_i,
    parallelism: ENV.fetch("EXTRACT_PARALLELISM", "5").to_i
  )
end
