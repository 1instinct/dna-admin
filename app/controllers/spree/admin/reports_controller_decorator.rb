module Spree
  module Admin
    ReportsController.class_eval do
      # Override the index action to add analytics dashboard
      def index
        @reports = reports_list
        
        # Add analytics data
        @date_range = params[:date_range] || '30'
        @start_date = @date_range.to_i.days.ago.beginning_of_day
        @end_date = Time.current.end_of_day
        
        # Order metrics
        @total_orders = Spree::Order.complete.where(completed_at: @start_date..@end_date).count
        @total_revenue = Spree::Order.complete.where(completed_at: @start_date..@end_date).sum(:total)
        @average_order_value = @total_orders > 0 ? (@total_revenue / @total_orders) : 0
        
        # User/Contact metrics  
        @new_users = Spree::User.where(created_at: @start_date..@end_date).count
        @new_contacts = Contact.where(created_at: @start_date..@end_date).count
        @total_users = Spree::User.count
        
        # Message metrics
        @total_messages = Message.where(created_at: @start_date..@end_date).count
        @unread_messages = Message.where(is_read: false, created_at: @start_date..@end_date).count
        @active_threads = ThreadTable.where(archived: false).count
        
        # Chart data
        prepare_charts_data
      end
      
      private
      
      def prepare_charts_data
        # Orders over time (daily)
        days = @date_range.to_i
        @orders_chart_data = (0...days).map do |i|
          date = i.days.ago.to_date
          count = Spree::Order.complete.where(
            completed_at: date.beginning_of_day..date.end_of_day
          ).count
          revenue = Spree::Order.complete.where(
            completed_at: date.beginning_of_day..date.end_of_day
          ).sum(:total).to_f
          
          {
            date: date.strftime('%m/%d'),
            orders: count,
            revenue: revenue.round(2)
          }
        end.reverse
        
        # Users growth
        @users_chart_data = (0...days).map do |i|
          date = i.days.ago.to_date
          users = Spree::User.where(
            created_at: date.beginning_of_day..date.end_of_day
          ).count
          contacts = Contact.where(
            created_at: date.beginning_of_day..date.end_of_day
          ).count
          
          {
            date: date.strftime('%m/%d'),
            users: users,
            contacts: contacts
          }
        end.reverse
        
        # Messages activity
        @messages_chart_data = (0...days).map do |i|
          date = i.days.ago.to_date
          total = Message.where(
            created_at: date.beginning_of_day..date.end_of_day
          ).count
          unread = Message.where(
            is_read: false,
            created_at: date.beginning_of_day..date.end_of_day
          ).count
          
          {
            date: date.strftime('%m/%d'),
            total: total,
            unread: unread
          }
        end.reverse
        
        # Order status breakdown
        @order_status_data = [
          { status: 'Complete', count: Spree::Order.where(state: 'complete', completed_at: @start_date..@end_date).count },
          { status: 'Cart', count: Spree::Order.where(state: 'cart').count },
          { status: 'Address', count: Spree::Order.where(state: 'address').count },
          { status: 'Delivery', count: Spree::Order.where(state: 'delivery').count },
          { status: 'Payment', count: Spree::Order.where(state: 'payment').count },
          { status: 'Canceled', count: Spree::Order.where(state: 'canceled').count }
        ].reject { |item| item[:count].zero? }
        
        # Top products
        @top_products = Spree::LineItem
          .joins(:order, :variant)
          .where('spree_orders.completed_at >= ?', @start_date)
          .where('spree_orders.state = ?', 'complete')
          .group('spree_variants.id')
          .select('spree_variants.id, spree_variants.sku, SUM(spree_line_items.quantity) as total_quantity, SUM(spree_line_items.quantity * spree_line_items.price) as total_sales')
          .order('total_quantity DESC')
          .limit(10)
      end
      
      def reports_list
        # Return the default Spree reports if available
        Spree::Admin::ReportsController::AVAILABLE_REPORTS rescue {}
      end
    end
  end
end
