module ReviewRequests
  # `rake reviews:backfill[days]`: schedules review requests for completed orders with a shipment
  # shipped in the last `days` days that have no request yet (orders that shipped before the
  # feature launched). They are due right away, staggered PER_HOUR to an hour so the hourly
  # dispatch sends them in batches. Same rules as ReviewRequests::Schedule (switched on, has an
  # email, not opted out, something to review). Safe to run again: orders with a request are skipped.
  #
  #   ReviewRequests::Backfill.call(days: 30) # => number of requests scheduled
  class Backfill
    PER_HOUR = 200

    def self.call(**args)
      new(**args).call
    end

    def initialize(days: 30, now: Time.current, per_hour: PER_HOUR, settings: Spree::ReviewSetting.current)
      @days = days.to_i.positive? ? days.to_i : 30
      @now = now
      @per_hour = [per_hour.to_i, 1].max
      @settings = settings
    end

    def call
      return 0 unless @settings.enabled

      scheduled = 0
      orders.find_each do |order|
        send_after = @now + (scheduled / @per_hour).hours
        request = Schedule.call(order, send_after: send_after, settings: @settings, now: @now)
        scheduled += 1 if request&.previously_new_record?
      end
      scheduled
    end

    def orders
      shipped = Spree::Shipment.where(state: 'shipped').where('shipped_at >= ?', @now - @days.days).select(:order_id)
      Spree::Order.complete.where(id: shipped).where.not(id: Spree::ReviewRequest.select(:order_id))
    end
  end
end
