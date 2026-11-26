require 'net/http'
require 'json'

class ExpoPushService
  EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send'.freeze
  BATCH_SIZE = 100

  # Send to all enabled devices
  def self.send_to_all(title:, body:, data: {})
    tokens = PushSubscription.enabled.pluck(:token)
    send_to_tokens(tokens: tokens, title: title, body: body, data: data)
  end

  # Send to a specific user's devices
  def self.send_to_user(user_id:, title:, body:, data: {})
    tokens = PushSubscription.enabled.for_user(user_id).pluck(:token)
    send_to_tokens(tokens: tokens, title: title, body: body, data: data)
  end

  # Send to a list of tokens
  def self.send_to_tokens(tokens:, title:, body:, data: {})
    return { sent: 0, errors: [] } if tokens.empty?

    messages = tokens.map do |token|
      {
        to: token,
        sound: 'default',
        title: title,
        body: body,
        data: data
      }
    end

    results = { sent: 0, errors: [] }
    messages.each_slice(BATCH_SIZE) do |batch|
      response = post_to_expo(batch)
      if response[:success]
        results[:sent] += batch.size
      else
        results[:errors] << response[:error]
      end
    end

    results
  end

  # Template: New product notification
  def self.notify_new_product(product)
    send_to_all(
      title: 'New Drop!',
      body: "#{product.name} is now available — check it out.",
      data: { type: 'new_product', productId: product.id, screen: 'ProductDetail' }
    )
  end

  # Template: Order shipped
  def self.notify_order_shipped(order)
    send_to_user(
      user_id: order.user_id,
      title: 'Your Order Shipped!',
      body: "Order ##{order.number} is on its way.",
      data: { type: 'order_update', orderNumber: order.number, screen: 'OrderDetail' }
    )
  end

  # Template: Promo/sale
  def self.notify_promo(title:, body:, promo_code: nil)
    send_to_all(
      title: title,
      body: body,
      data: { type: 'promo', promoCode: promo_code, screen: 'Shop' }.compact
    )
  end

  private

  def self.post_to_expo(messages)
    uri = URI(EXPO_PUSH_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = messages.to_json

    response = http.request(request)

    if response.code.to_i == 200
      { success: true, data: JSON.parse(response.body) }
    else
      { success: false, error: "Expo API returned #{response.code}: #{response.body}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
