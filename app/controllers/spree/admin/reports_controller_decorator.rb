module Spree
  module Admin
    # The analytics dashboard on /admin/reports.
    #
    # Each series is one grouped query (not one query per day), so 365 days
    # costs the same handful of queries as 7.
    module ReportsControllerDecorator
      DATE_RANGES = %w[7 30 90 365].freeze

      def index
        super

        @date_range = DATE_RANGES.include?(params[:date_range]) ? params[:date_range] : '30'
        days = @date_range.to_i
        @end_date = Time.current.end_of_day
        @start_date = (days - 1).days.ago.beginning_of_day
        range = @start_date..@end_date

        completed = Spree::Order.complete.where(completed_at: range)
        @total_orders = completed.count
        @total_revenue = completed.sum(:total)
        @average_order_value = @total_orders.positive? ? (@total_revenue / @total_orders) : 0

        @new_users = Spree::User.where(created_at: range).count
        @new_contacts = Contact.where(created_at: range).count
        @total_users = Spree::User.count

        messages = Message.where(created_at: range)
        @total_messages = messages.count
        @unread_messages = messages.where(is_read: false).count
        @active_threads = ThreadTable.where(archived: false).count

        prepare_charts_data(completed, messages)
      end

      private

      def prepare_charts_data(completed, messages)
        dates = (@start_date.to_date..@end_date.to_date).to_a

        orders = per_day(completed, 'spree_orders.completed_at')
        revenue = per_day(completed, 'spree_orders.completed_at', 'SUM(spree_orders.total)')
        @orders_chart_data = dates.map do |date|
          { date: date.strftime('%m/%d'), orders: orders[date].to_i, revenue: revenue[date].to_f.round(2) }
        end

        users = per_day(Spree::User.where(created_at: @start_date..@end_date), 'spree_users.created_at')
        contacts = per_day(Contact.where(created_at: @start_date..@end_date), 'contacts.created_at')
        @users_chart_data = dates.map do |date|
          { date: date.strftime('%m/%d'), users: users[date].to_i, contacts: contacts[date].to_i }
        end

        total = per_day(messages, 'messages.created_at')
        unread = per_day(messages.where(is_read: false), 'messages.created_at')
        @messages_chart_data = dates.map do |date|
          { date: date.strftime('%m/%d'), total: total[date].to_i, unread: unread[date].to_i }
        end

        @order_status_data = [
          { status: 'Complete', count: @total_orders },
          { status: 'Cart', count: Spree::Order.where(state: 'cart').count },
          { status: 'Address', count: Spree::Order.where(state: 'address').count },
          { status: 'Delivery', count: Spree::Order.where(state: 'delivery').count },
          { status: 'Payment', count: Spree::Order.where(state: 'payment').count },
          { status: 'Canceled', count: Spree::Order.where(state: 'canceled').count }
        ].reject { |item| item[:count].zero? }

        # Variants, not line items: the view calls .sku, which on a LineItem
        # needs the variant_id this grouped select does not load.
        @top_products = Spree::Variant
                        .joins(line_items: :order)
                        .merge(completed)
                        .group('spree_variants.id')
                        .select('spree_variants.id, spree_variants.sku, ' \
                                'SUM(spree_line_items.quantity) AS total_quantity, ' \
                                'SUM(spree_line_items.quantity * spree_line_items.price) AS total_sales')
                        .order('total_quantity DESC')
                        .limit(10)
      end

      # { Date => value } for the scope, bucketed by the given timestamp column
      # in the app's time zone (timestamps are stored in UTC).
      def per_day(scope, column, aggregate = 'COUNT(*)')
        day = Arel.sql(ActiveRecord::Base.sanitize_sql_array(
          ["DATE(#{column} AT TIME ZONE 'UTC' AT TIME ZONE ?)", Time.zone.tzinfo.name]
        ))
        scope.unscope(:order).group(day).pluck(day, Arel.sql(aggregate)).to_h
      end
    end
  end
end

Spree::Admin::ReportsController.prepend(Spree::Admin::ReportsControllerDecorator)
