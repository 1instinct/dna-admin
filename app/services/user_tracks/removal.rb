module UserTracks
  # Deletes a track for its owner: the row is soft-deleted (it still counts for the quota, the
  # hourly limit and the spend breaker) and its audio is purged at once. A job still finishing it
  # sees deleted_at under the same row lock and throws its result away.
  module Removal
    module_function

    def call(track, now: Time.current)
      blob = nil
      track.with_lock do
        unless track.deleted_at
          if track.audio.attached?
            blob = track.audio.blob
            track.audio.detach
          end
          track.update_columns(deleted_at: now, updated_at: now)
        end
      end
      purge(blob, track)
      true
    end

    def purge(blob, track)
      blob&.purge
    rescue StandardError => e
      Rails.logger.error("[user_tracks] track #{track.id} audio purge failed: #{e.class} blob_key=#{blob.key}")
    end
  end
end
