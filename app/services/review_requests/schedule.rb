module ReviewRequests
  # Schedules the review request email for an order that has shipped. Called from
  # Spree::Shipment#after_ship (Spree::ShipmentReviewRequestDecorator) and by the backfill.
  #
  #   ReviewRequests::Schedule.call(order)                         # send_after = last shipped_at + delay
  #   ReviewRequests::Schedule.call(order, send_after: Time.current) # backfill
  #
  # One request per order. While it is still `scheduled`, a later shipment moves send_after to the
  # last shipment's shipped_at + delay; once sent (or opted out, expired...) it is left alone.
  # Delay: international_request_delay_days when the ship address is in another country than the
  # store's default (the order's store, else the default store, else Spree::Config[:default_country_id]),
  # else request_delay_days. expires_at = send_after + request_expiry_days.
  #
  # Skipped (returns nil): reviews switched off, no email, the address opted out of review emails,
  # or nothing on the order can be reviewed yet (Reviews::Eligibility needs shipped items, so call
  # this after the shipment's state is saved). Wholesale orders get requests too.
  class Schedule
    def self.call(order, **options)
      new(order, **options).call
    end

    attr_reader :order, :settings, :now

    def initialize(order, send_after: nil, settings: Spree::ReviewSetting.current, now: Time.current)
      @order = order
      @send_after = send_after
      @settings = settings
      @now = now
    end

    def call
      return unless settings.enabled
      return if order.nil? || order.email.blank?
      return if Spree::ReviewRequest.opted_out?(order.email)
      return if Reviews::Eligibility.for_order(order).empty?

      send_after = @send_after || (last_shipped_at + delay_days.days)
      attrs = { send_after: send_after, expires_at: send_after + settings.request_expiry_days.days }

      request = Spree::ReviewRequest.find_by(order_id: order.id)
      return reschedule(request, attrs) if request

      create(attrs)
    end

    def delay_days
      international? ? settings.international_request_delay_days : settings.request_delay_days
    end

    def international?
      country_id = order.ship_address&.country_id
      # Not Spree::Store.default: that one is cached.
      store = order.store || Spree::Store.find_by(default: true)
      home_id = store&.default_country_id || Spree::Config[:default_country_id]
      country_id.present? && home_id.present? && country_id.to_i != home_id.to_i
    end

    private

    def last_shipped_at
      order.shipments.where(state: 'shipped').maximum(:shipped_at) || now
    end

    def reschedule(request, attrs)
      request.update!(attrs.merge(email: order.email)) if request.status == 'scheduled'
      request
    end

    def create(attrs)
      # A savepoint: a concurrent insert for the same order mustn't abort the caller's transaction
      # (after_ship runs inside the shipment's state transition).
      Spree::ReviewRequest.transaction(requires_new: true) do
        Spree::ReviewRequest.create!(attrs.merge(order: order, user: order.user, email: order.email, status: 'scheduled'))
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      Spree::ReviewRequest.find_by(order_id: order.id) || raise
    end
  end
end
