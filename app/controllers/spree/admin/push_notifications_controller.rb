class Spree::Admin::PushNotificationsController < Spree::Admin::BaseController
  before_action :set_session

  def index
    @token_count = PushSubscription.enabled.count
    @ios_count = PushSubscription.enabled.ios.count
    @android_count = PushSubscription.enabled.android.count
    @users_with_tokens = PushSubscription.enabled.select(:user_id).distinct.count

    @notifications = PushNotification.recent.page(params[:page]).per(20)
    @products = Spree::Product.order(created_at: :desc).limit(10)
    @users = Spree::User.order(created_at: :desc).limit(50)
  end

  def send_notification
    title = params[:title].to_s.strip
    body = params[:body].to_s.strip
    target = params[:target] || 'all'
    target_user_id = params[:target_user_id]
    notification_type = params[:notification_type] || 'custom'

    if title.blank? || body.blank?
      flash[:error] = 'Title and body are required.'
      redirect_to admin_push_notifications_path and return
    end

    data = { type: notification_type }
    data[:screen] = params[:screen] if params[:screen].present?
    data[:promoCode] = params[:promo_code] if params[:promo_code].present?

    results = case target
              when 'user'
                if target_user_id.blank?
                  flash[:error] = 'Please select a user.'
                  redirect_to admin_push_notifications_path and return
                end
                ExpoPushService.send_to_user(user_id: target_user_id, title: title, body: body, data: data)
              else
                ExpoPushService.send_to_all(title: title, body: body, data: data)
              end

    notification = PushNotification.create!(
      title: title,
      body: body,
      notification_type: notification_type,
      data: data,
      target: target,
      target_user_id: target_user_id,
      sent_count: results[:sent],
      error_count: results[:errors].size,
      errors_log: results[:errors].any? ? results[:errors].join("\n") : nil,
      status: results[:errors].any? && results[:sent] == 0 ? 'failed' : 'sent',
      sent_by: try_spree_current_user
    )

    if results[:errors].any?
      flash[:error] = "Sent to #{results[:sent]} devices with #{results[:errors].size} error(s)."
    else
      flash[:success] = "Notification sent to #{results[:sent]} device(s)."
    end

    redirect_to admin_push_notifications_path
  end

  def notify_product
    product = Spree::Product.find(params[:product_id])
    results = ExpoPushService.notify_new_product(product)

    PushNotification.create!(
      title: 'New Drop!',
      body: "#{product.name} is now available — check it out.",
      notification_type: 'product',
      data: { type: 'new_product', productId: product.id },
      target: 'all',
      sent_count: results[:sent],
      error_count: results[:errors].size,
      errors_log: results[:errors].any? ? results[:errors].join("\n") : nil,
      status: results[:errors].any? && results[:sent] == 0 ? 'failed' : 'sent',
      sent_by: try_spree_current_user
    )

    flash[:success] = "Product notification sent to #{results[:sent]} device(s)."
    redirect_to admin_push_notifications_path
  end

  private

  def set_session
    session[:return_to] = request.url
  end
end
