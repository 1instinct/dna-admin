module Uploads
  # Purges blobs that were never attached (abandoned direct uploads) once they are older than
  # older_than. Returns how many were purged. Run daily: rake uploads:sweep_unattached.
  module UnattachedSweeper
    module_function

    def call(older_than: 1.day, now: Time.current)
      count = 0
      ActiveStorage::Blob.unattached.where('active_storage_blobs.created_at < ?', now - older_than).find_each do |blob|
        blob.purge
        count += 1
      rescue StandardError => e
        Rails.logger.error("[uploads] purge failed for blob #{blob.id}: #{e.class}")
      end
      count
    end
  end
end
