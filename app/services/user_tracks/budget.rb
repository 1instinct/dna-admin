module UserTracks
  # The global daily spend breaker: estimated generator spend on tracks started (or submitted
  # again) today, UTC, against UserTracks.config.daily_budget_usd. Deleted and failed tracks count:
  # the provider was paid either way. A track's estimate is reserved when it starts, and each
  # regeneration's before it is sent, so tracks still queued, and submits that timed out, count too.
  #
  # Check and reserve together under Budget.lock! (a transaction-scoped advisory lock shared by
  # every user), so two users' requests can't both pass on the last of the budget.
  module Budget
    # pg_advisory_xact_lock(int, int): "UTrb", 0.
    LOCK = [0x5554_7262, 0].freeze

    module_function

    def allow?(cost, now: Time.current)
      spent_today(now: now) + cost.to_f <= UserTracks.config.daily_budget_usd.to_f + 1e-9
    end

    def spent_today(now: Time.current)
      day = now.utc.beginning_of_day
      Spree::UserTrack.where('created_at >= :day OR submitted_at >= :day', day: day).
        sum(Arel.sql("COALESCE((generation->>'costUsd')::numeric, 0)")).to_f
    end

    # Call inside a transaction; held until it ends.
    def lock!
      sql = Spree::UserTrack.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', *LOCK])
      Spree::UserTrack.connection.execute(sql)
    end
  end
end
