module UserTracks
  # Starts a new track for its user: checks the limits, debits a credit (saves the track) and
  # queues its generation. The checks and the save run under a per-user advisory lock, so two
  # requests at once can't both pass the in-flight, hourly or quota checks.
  #
  #   UserTracks::Start.call(track) # => track, or raises one of the errors below
  #
  # InFlight     the user already has a track queued, generating or finalizing (409)
  # RateLimited  more than UserTracks.config.hourly_limit tracks started in the last hour (429)
  # Quota::Exhausted  no credit left this month (402)
  module Start
    class InFlight < StandardError; end
    class RateLimited < StandardError; end

    # Namespace for pg_advisory_xact_lock(int, int): "UTrk".
    LOCK_NAMESPACE = 0x5554_726B

    module_function

    def call(track, now: Time.current)
      track.title ||= track.default_title
      Spree::UserTrack.transaction do
        lock(track.user_id)
        raise InFlight if Spree::UserTrack.kept.in_flight.where(user_id: track.user_id).exists?
        raise RateLimited if started_last_hour(track.user_id, now) >= UserTracks.config.hourly_limit

        UserTracks::Quota.debit!(track)
      end
      track
    end

    # Deleted tracks count too, so deleting doesn't reset the limit.
    def started_last_hour(user_id, now)
      Spree::UserTrack.where(user_id: user_id).where('created_at > ?', now - 1.hour).count
    end

    def lock(user_id)
      sql = Spree::UserTrack.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', LOCK_NAMESPACE, user_id.to_i])
      Spree::UserTrack.connection.execute(sql)
    end
  end
end
