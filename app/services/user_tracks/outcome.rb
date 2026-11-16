module UserTracks
  # How a track ends when it doesn't become ready: failed, with plain words for its owner and the
  # credit refunded (once). Runs under the track's row lock; a deleted track, or one already
  # finished, is left as it is.
  module Outcome
    MESSAGES = {
      'provider_unavailable' => "The track generator isn't available right now.",
      'provider_failed' => "The generator couldn't make this track.",
      'download_failed' => "The track couldn't be fetched from the generator.",
      'analysis_failed' => "The track couldn't be checked.",
      'tempo_drift' => "It didn't hold the tempo, so it wouldn't loop in time.",
      'no_loop_window' => "No clean loop came out of it.",
      'timeout' => 'It took too long to make.',
      'lost' => 'It got lost on the way. Try again.'
    }.freeze

    module_function

    # true when this call failed the track.
    def fail!(track, code, now: Time.current)
      code = code.to_s
      blob = nil
      failed = false
      track.with_lock do
        if !track.deleted_at && !track.ready? && !track.failed?
          if track.audio.attached?
            blob = track.audio.blob
            track.audio.detach
          end
          generation = track.generation.merge('failure' => code)
          generation.delete('candidate')
          track.update_columns(status: 'failed', error: MESSAGES.fetch(code, MESSAGES['provider_failed']),
                               generation: generation, updated_at: now)
          failed = true
        end
      end
      return false unless failed

      UserTracks::Quota.refund!(track, now: now)
      UserTracks::Removal.purge(blob, track)
      Rails.logger.info("[user_tracks] track #{track.id} failed: #{code}, credit refunded")
      true
    end
  end
end
