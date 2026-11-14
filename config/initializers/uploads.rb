# Direct uploads (app/services/uploads.rb holds Uploads.config).
#
# Defaults: audio (wav/aiff/flac/mp3) up to 50 MB, images (png/jpg/webp) up to 10 MB, json/glsl
# text up to 256 KB; 100 upload slots per user per hour. A digital asset's files total at most
# DigitalAssets.config.max_asset_bytes (1 GB).
#
# Blobs created for direct uploads that are never attached are purged after a day by
# Uploads::UnattachedSweeper (rake uploads:sweep_unattached; run it daily from a scheduler).
#
# Production storage must accept browser PUTs to the direct upload URL: the bucket's CORS rules
# allow PUT from the storefront origin with the Content-MD5, Content-Type and Content-Disposition
# headers.
#
#   Rails.application.config.to_prepare do
#     Uploads.configure { |c| c.rules[:image][:max_bytes] = 5.megabytes }
#   end
