module UserTracks
  # Sends a queued track to the generator: a new seed each attempt, the webhook URL with the
  # track's token, and the attempt recorded in `generation` (seeds, requestIds, requestId,
  # attempts, durationSec, costUsd). The track moves queued -> generating with one conditional
  # update, so a job run twice (or for a deleted track) does nothing. If the provider can't take
  # it, the track fails and its credit is refunded.
  class SubmitJob < ApplicationJob
    queue_as :default

    def perform(track_id)
      now = Time.current
      # The previous attempt's request id goes too, so nothing finalises it again while this one is
      # being submitted.
      claimed = Spree::UserTrack.where(id: track_id, status: 'queued', deleted_at: nil).
                update_all(["status = 'generating', checked_at = NULL, updated_at = ?, generation = generation - 'requestId'", now])
      return unless claimed == 1

      track = Spree::UserTrack.find(track_id)
      input = UserTracks::Prompt.build(track)
      request_id = UserTracks::Fal.new.submit(input, webhook_url: track.webhook_url)
      record(track, input, request_id, now)
      Rails.logger.info("[user_tracks] track #{track.id} submitted, attempt #{track.generation['attempts']}, " \
                        "request_id=#{request_id}")
    rescue UserTracks::Fal::Error => e
      Rails.logger.warn("[user_tracks] track #{track_id} submit failed: #{e.code}")
      UserTracks::Outcome.fail!(track || Spree::UserTrack.find(track_id), 'provider_unavailable')
    end

    private

    def record(track, input, request_id, now)
      generation = track.generation.deep_dup
      attempts = generation['attempts'].to_i + 1
      cost = (input[:duration] * UserTracks.config.price_per_second).round(6)
      generation.merge!(
        'provider' => 'fal',
        'model' => UserTracks.config.fal_model,
        'seeds' => Array(generation['seeds']) + [input[:seed]],
        'requestIds' => Array(generation['requestIds']) + [request_id],
        'requestId' => request_id,
        'attempts' => attempts,
        'durationSec' => input[:duration],
        # The first attempt's estimate was reserved when the track started.
        'costUsd' => (attempts == 1 ? cost : generation['costUsd'].to_f + cost).round(6)
      )
      track.update_columns(generation: generation, submitted_at: now, updated_at: now)
    end
  end
end
