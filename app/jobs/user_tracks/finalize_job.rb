require 'tmpdir'

module UserTracks
  # Finishes a generating track (after fal's webhook, or from reconcile):
  #
  # 1. Claims it: generating -> finalizing with one conditional update. A second webhook, a
  #    reconcile after the webhook, or a deleted track finds nothing to claim and does nothing.
  #    Each claim counts in generation.finalizeAttempts (reset by each new submit): a track that
  #    has been claimed MAX_ATTEMPTS times (fal or the download unreachable each time, or the dyno
  #    restarting mid-finalise) is failed with its credit refunded instead of claimed again.
  # 2. Asks fal for the status and the result with Rails' own key (a webhook body is never used).
  #    Still running: back to generating. Failed: failed, credit refunded. fal unreachable: back to
  #    generating, for reconcile to try again.
  # 3. Downloads the audio, runs track_post (UserTracks::Post), records its analysis and applies
  #    UserTracks::Decide: ready (the loop attached, the profile and loop stored), regenerate (back
  #    to queued with SubmitJob, the loop kept as the candidate after a confident key miss) or
  #    failed with the credit refunded.
  #
  # The new blob is uploaded before the row lock and attached under it; when the track was
  # deleted meanwhile (soft, or its row gone with its account) the blob is purged, so nothing is
  # left behind.
  class FinalizeJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 3
    ATTEMPTS_SQL = "COALESCE((generation->>'finalizeAttempts')::int, 0)".freeze
    CLAIM_SQL = "status = 'finalizing', updated_at = ?, " \
                "generation = jsonb_set(generation, '{finalizeAttempts}', to_jsonb(#{ATTEMPTS_SQL} + 1))".freeze

    def perform(track_id)
      track = claim(track_id)
      return unless track

      finalize(track)
    rescue UserTracks::Fal::Error => e
      e.code == :unreachable ? release(track) : UserTracks::Outcome.fail!(track, 'provider_failed')
    rescue UserTracks::Download::Error => e
      Rails.logger.warn("[user_tracks] track #{track_id} download failed: #{e.message}")
      e.code == :unreachable ? release(track) : UserTracks::Outcome.fail!(track, 'download_failed')
    rescue UserTracks::Post::Error => e
      Rails.logger.error("[user_tracks] track #{track_id} post-processing failed: #{e.message}")
      UserTracks::Outcome.fail!(track, 'analysis_failed')
    rescue StandardError => e
      Rails.logger.error("[user_tracks] track #{track_id} finalise failed: #{e.class}: #{e.message}")
      UserTracks::Outcome.fail!(track, 'analysis_failed') if track
    end

    private

    def claim(track_id)
      claimable = Spree::UserTrack.where(id: track_id, status: 'generating', deleted_at: nil).
                  where("generation->>'requestId' IS NOT NULL")
      claimed = claimable.where("#{ATTEMPTS_SQL} < ?", MAX_ATTEMPTS).update_all([CLAIM_SQL, Time.current])
      return Spree::UserTrack.find(track_id) if claimed == 1

      exhausted = claimable.find_by(id: track_id)
      return unless exhausted

      Rails.logger.warn("[user_tracks] track #{track_id} not finalised after #{MAX_ATTEMPTS} attempts")
      UserTracks::Outcome.fail!(exhausted, 'finalize_failed')
      nil
    end

    def release(track)
      return unless track

      Spree::UserTrack.where(id: track.id, status: 'finalizing').update_all(status: 'generating', updated_at: Time.current)
    end

    def finalize(track)
      fal = UserTracks::Fal.new
      request_id = track.generation['requestId']
      case fal.status(request_id)
      when :failed then return UserTracks::Outcome.fail!(track, 'provider_failed')
      when :in_queue, :in_progress then return release(track)
      end

      audio = fal.result(request_id)
      Dir.mktmpdir('user-track') do |dir|
        in_path = File.join(dir, 'generated')
        out_path = File.join(dir, 'loop.flac')
        UserTracks::Download.call(audio[:audio_url], to: in_path)
        analysis = UserTracks::Post.call(in_path: in_path, out_path: out_path, track: track)
        record_analysis(track, analysis)
        apply(track, UserTracks::Decide.call(track, analysis), analysis, out_path)
      end
    end

    def record_analysis(track, analysis)
      generation = track.generation.deep_dup
      generation['analysis'] = Array(generation['analysis']) + [analysis.merge('attempt' => generation['attempts'].to_i)]
      track.update_columns(generation: generation)
    end

    def apply(track, decision, analysis, out_path)
      case decision.action
      when :fail then UserTracks::Outcome.fail!(track, decision.reason)
      when :regenerate then regenerate(track, decision, analysis, out_path)
      when :ready then ready(track, decision, analysis, out_path)
      end
    end

    def ready(track, decision, analysis, out_path)
      if decision.use == :candidate && !track.audio.attached?
        return UserTracks::Outcome.fail!(track, decision.reason || 'analysis_failed')
      end

      kept = decision.use == :candidate ? track.generation.dig('candidate', 'analysis') : analysis
      blob = decision.use == :current ? upload(out_path) : nil
      key = decision.profile.values_at('key', 'scale')
      replaced = update_locked(track, blob) do |locked, now|
        generation = locked.generation.except('candidate')
        locked.update_columns(status: 'ready', ready_at: now, updated_at: now, generation: generation,
                              profile: decision.profile, title: locked.default_title(key: key[0], scale: key[1]),
                              loop_info: { 'sampleRate' => kept['sampleRate'], 'loopSamples' => kept['loopSamples'] })
      end
      return unless replaced

      Rails.logger.info("[user_tracks] track #{track.id} ready (attempt #{track.generation['attempts']}, " \
                        "#{decision.use}, key #{decision.profile['profileSource']['key']})")
    end

    def regenerate(track, decision, analysis, out_path)
      blob = decision.keep_candidate ? upload(out_path) : nil
      queued = update_locked(track, blob) do |locked, now|
        generation = locked.generation.merge('retryReason' => decision.reason)
        generation['candidate'] = { 'attempt' => generation['attempts'].to_i, 'analysis' => analysis } if blob
        locked.update_columns(status: 'queued', updated_at: now, generation: generation)
      end
      return unless queued

      Rails.logger.info("[user_tracks] track #{track.id} regenerating: #{decision.reason}")
      UserTracks::SubmitJob.perform_later(track.id)
    end

    # Under the row lock: when the track is still this job's (finalizing, not deleted), attaches
    # `blob` (if any) in place of the current audio and yields; else purges `blob`. The replaced
    # audio is purged after the lock. Answers whether it applied.
    def update_locked(track, blob)
      old_blob = nil
      applied = false
      begin
        track.with_lock do
          if track.finalizing? && !track.deleted_at
            # Attachment rows by hand: audio.attach would save the record (and re-run validations).
            if blob
              old = track.audio_attachment
              old_blob = old&.blob
              old&.delete
              ActiveStorage::Attachment.create!(name: 'audio', record: track, blob: blob)
              track.reload
            end
            yield track, Time.current
            applied = true
          end
        end
      rescue ActiveRecord::RecordNotFound
        # The row went with its account (AccountDeletion) after the upload.
        Rails.logger.info("[user_tracks] track #{track.id} was removed while finalising")
      end
      UserTracks::Removal.purge(applied ? old_blob : blob, track)
      applied
    end

    def upload(path)
      File.open(path, 'rb') do |io|
        ActiveStorage::Blob.create_and_upload!(io: io, filename: 'loop.flac', content_type: 'audio/flac', identify: false)
      end
    end
  end
end
