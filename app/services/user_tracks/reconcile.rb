module UserTracks
  # Brings a user's overdue tracks up to date when they list their tracks. ActiveJob runs on the
  # in-process async adapter, so jobs lost to a dyno restart (or a webhook that never came) are
  # recovered here, with no worker or scheduler:
  #
  # - queued for longer than reconcile_after: SubmitJob again (its claim makes a repeat harmless);
  # - finalizing for longer than finalizing_stale_after: back to generating, then as below;
  # - generating with no request id for longer than reconcile_after (lost mid-submit): failed;
  # - generating, submitted more than reconcile_after ago and not checked within check_every: ask
  #   fal. Completed: FinalizeJob. Failed: failed. Still running past give_up_after: failed
  #   ("timeout"). fal unreachable: left for next time.
  # Failed tracks get their credit back. Deleted tracks are left alone.
  module Reconcile
    module_function

    def call(user, now: Time.current)
      config = UserTracks.config
      tracks = Spree::UserTrack.kept.where(user_id: user.id)
      tracks.where(status: 'finalizing').where('updated_at < ?', now - config.finalizing_stale_after).
        update_all(status: 'generating', checked_at: nil, updated_at: now)
      tracks.where(status: 'queued').where('updated_at < ?', now - config.reconcile_after).
        pluck(:id).each { |id| UserTracks::SubmitJob.perform_later(id) }
      overdue(tracks, now, config).each { |track| check(track, now, config) }
    end

    def overdue(tracks, now, config)
      cutoff = now - config.reconcile_after
      tracks.where(status: 'generating').
        where('submitted_at < :cutoff OR (submitted_at IS NULL AND updated_at < :cutoff)', cutoff: cutoff).
        where('checked_at IS NULL OR checked_at < ?', now - config.check_every).to_a
    end

    def check(track, now, config)
      request_id = track.generation['requestId']
      return UserTracks::Outcome.fail!(track, 'lost') if request_id.blank?

      track.update_columns(checked_at: now)
      case UserTracks::Fal.new.status(request_id)
      when :completed then UserTracks::FinalizeJob.perform_later(track.id)
      when :failed then UserTracks::Outcome.fail!(track, 'provider_failed')
      else
        UserTracks::Outcome.fail!(track, 'timeout') if track.submitted_at && track.submitted_at < now - config.give_up_after
      end
    rescue UserTracks::Fal::Error => e
      Rails.logger.warn("[user_tracks] reconcile of track #{track.id} skipped: #{e.code}")
    end
  end
end
