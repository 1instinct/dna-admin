module UserTracks
  # Credits: UserTracks.config.monthly_free tracks per user per calendar month (UTC). The track row
  # is the ledger entry: each one made this month uses a credit unless credit_refunded_at is set.
  # Deleted (soft-deleted) tracks still count, so deleting doesn't buy a new track.
  module Quota
    class Exhausted < StandardError; end

    module_function

    def remaining(user, now: Time.current)
      [UserTracks.config.monthly_free - used(user, now: now), 0].max
    end

    def used(user, now: Time.current)
      Spree::UserTrack.where(user_id: user.id, credit_refunded_at: nil).
        where('created_at >= ?', month_start(now)).count
    end

    def resets_at(now: Time.current)
      month_start(now).next_month
    end

    # Saves the new track as the debit, or raises Exhausted with no credit left. Callers hold
    # UserTracks::Start's per-user lock so two requests can't both take the last credit.
    def debit!(track)
      raise Exhausted unless remaining(track.user) > 0

      track.save!
      track
    end

    # Gives the credit back once: true the first time, false after (the conditional update is the
    # guard, so concurrent refunds can't both count).
    def refund!(track, now: Time.current)
      changed = Spree::UserTrack.where(id: track.id, credit_refunded_at: nil).
                update_all(credit_refunded_at: now, updated_at: now)
      track.credit_refunded_at ||= now if changed == 1
      changed == 1
    end

    def month_start(now)
      now.utc.beginning_of_month
    end
  end
end
