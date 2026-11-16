module UserTracks
  # The global daily spend breaker: estimated generator spend on tracks started (or submitted
  # again) today, UTC, against UserTracks.config.daily_budget_usd. Deleted and failed tracks count:
  # the provider was paid either way. A track's estimate is reserved when it starts, so tracks
  # still queued count too.
  module Budget
    module_function

    def allow?(cost, now: Time.current)
      spent_today(now: now) + cost.to_f <= UserTracks.config.daily_budget_usd.to_f + 1e-9
    end

    def spent_today(now: Time.current)
      day = now.utc.beginning_of_day
      Spree::UserTrack.where('created_at >= :day OR submitted_at >= :day', day: day).
        sum(Arel.sql("COALESCE((generation->>'costUsd')::numeric, 0)")).to_f
    end
  end
end
