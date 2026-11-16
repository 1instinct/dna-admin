module UserTracks
  # Sends a queued track to the generator: a new seed each attempt, the webhook URL with the
  # track's token, and the attempt recorded in `generation` (seeds, requestIds, requestId,
  # attempts, durationSec, costUsd).
  #
  # - The claim moves queued -> generating with one conditional update, so a job run twice (or
  #   for a deleted track) does nothing. It clears the previous attempt's request id and
  #   submitted_at, so nothing finalises the old attempt, and reconcile times a lost submit from
  #   the claim (updated_at), not from the previous submit.
  # - A regeneration's cost is checked against the daily budget and reserved before the POST,
  #   under the budget lock (the first attempt's was reserved when the track started). The cost
  #   stays counted when the POST fails or times out: fal may have taken the job anyway. Over the
  #   budget the track fails ("busy") with its credit refunded.
  # - The attempt is recorded only while the track is still this job's (generating, no request
  #   id), so a track failed meanwhile isn't overwritten.
  # If the provider can't take it, the track fails and its credit is refunded.
  class SubmitJob < ApplicationJob
    queue_as :default

    CLAIM_SQL = "status = 'generating', checked_at = NULL, submitted_at = NULL, updated_at = ?, " \
                "generation = generation - 'requestId'".freeze

    def perform(track_id)
      claimed = Spree::UserTrack.where(id: track_id, status: 'queued', deleted_at: nil).
                update_all([CLAIM_SQL, Time.current])
      return unless claimed == 1

      track = Spree::UserTrack.find(track_id)
      input = UserTracks::Prompt.build(track)
      return UserTracks::Outcome.fail!(track, 'busy') unless reserve(track, input)

      request_id = UserTracks::Fal.new.submit(input, webhook_url: track.webhook_url)
      if record(track, input, request_id)
        Rails.logger.info("[user_tracks] track #{track.id} submitted, attempt #{track.generation['attempts']}, " \
                          "request_id=#{request_id}")
      else
        Rails.logger.warn("[user_tracks] track #{track.id} changed while submitting; request_id=#{request_id} not recorded")
      end
    rescue UserTracks::Fal::Error => e
      Rails.logger.warn("[user_tracks] track #{track_id} submit failed: #{e.code}")
      UserTracks::Outcome.fail!(track || Spree::UserTrack.find(track_id), 'provider_unavailable')
    rescue ActiveRecord::RecordNotFound
      nil
    end

    private

    # true when the attempt may go out. The first attempt's cost was checked and reserved by
    # UserTracks::Start (it is set here only for a track that didn't come through it); a
    # regeneration's is checked and added to costUsd under the budget lock.
    def reserve(track, input)
      cost = (input[:duration] * UserTracks.config.price_per_second).round(6)
      if track.generation['attempts'].to_i.zero?
        track.update_columns(generation: track.generation.merge('costUsd' => cost)) unless track.generation.key?('costUsd')
        return true
      end

      Spree::UserTrack.transaction do
        UserTracks::Budget.lock!
        next false unless UserTracks::Budget.allow?(cost)

        reserved = (track.generation['costUsd'].to_f + cost).round(6)
        track.update_columns(generation: track.generation.merge('costUsd' => reserved))
        true
      end
    end

    def record(track, input, request_id, now: Time.current)
      generation = track.generation.deep_dup
      generation.delete('finalizeAttempts')
      generation.merge!(
        'provider' => 'fal',
        'model' => UserTracks.config.fal_model,
        'seeds' => Array(generation['seeds']) + [input[:seed]],
        'requestIds' => Array(generation['requestIds']) + [request_id],
        'requestId' => request_id,
        'attempts' => generation['attempts'].to_i + 1,
        'durationSec' => input[:duration]
      )
      recorded = Spree::UserTrack.where(id: track.id, status: 'generating').
                 where("generation->>'requestId' IS NULL").
                 update_all(generation: generation, submitted_at: now, updated_at: now)
      track.assign_attributes(generation: generation, submitted_at: now) if recorded == 1
      recorded == 1
    end
  end
end
