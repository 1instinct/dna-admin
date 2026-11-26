# The post-purchase review request ("How's your order?") and its one reminder. Sent inline by
# ReviewRequests::Dispatch (`rake reviews:dispatch`), which passes the raw link token: only its
# SHA256 is stored on the request, so the token exists in this email and nowhere else.
#
# Lists each item of the order not yet reviewed with five star links to the storefront's
# /review/[token] page (`?item=<line_item_id>&rating=<n>`), plus an opt-out link. Copy stays
# neutral (FTC 16 CFR 465): it asks what the customer thinks, never for a positive review, and
# mentions points the same way for every rating.
class ReviewRequestMailer < ApplicationMailer
  RATINGS = (1..5).freeze

  def request_review(request, token)
    build(request, token, reminder: false)
  end

  def reminder(request, token)
    build(request, token, reminder: true)
  end

  private

  def build(request, token, reminder:)
    settings = Spree::ReviewSetting.current
    @review_request = request
    @order = request.order
    @reminder = reminder
    store = @order.store || Spree::Store.default
    @store_name = store&.name.to_s.strip.presence
    @review_url = review_url(token)
    @opt_out_url = "#{@review_url}?opt_out=1"
    @items = request.items.reject(&:existing_review).map { |item| item_view(item, token) }
    @points = settings.points_per_review.to_i.positive? ? settings.points_per_review : nil
    @photo_bonus = @points && settings.points_photo_bonus.to_i.positive? ? settings.points_photo_bonus : nil
    @expires_on = request.expires_at&.to_date
    @subject = subject_line
    from = store&.mail_from_address.presence
    message = mail(**{ to: request.email, subject: @subject, from: from }.compact)
    # Dispatch leaves the request as it was when delivery fails, so the next run retries.
    message.raise_delivery_errors = true
    message
  end

  def subject_line
    order = @store_name ? "your #{@store_name} order" : 'your order'
    @reminder ? "Reminder: how's #{order}?" : "How's #{order}?"
  end

  def review_url(token)
    "#{SITE_URL.to_s.chomp('/')}/review/#{token}"
  end

  def item_view(item, token)
    name = item.product.name
    stars = RATINGS.map do |rating|
      { rating: rating, url: "#{review_url(token)}?item=#{item.line_item.id}&rating=#{rating}",
        label: "Rate #{name} #{rating} out of 5" }
    end
    { line_item_id: item.line_item.id, name: name, variant_label: Spree::Review.new(variant: item.variant).variant_label,
      image_url: image_url(item.variant, item.product), stars: stars }
  end

  # An absolute URL for the variant's (else the product's) image, or nil when there is none or no
  # host is configured (Rails.application.routes.default_url_options): an email can't use a path.
  def image_url(variant, product)
    image = variant&.images&.first || product.master.images.first || product.variant_images.first
    path = image&.attachment&.attached? && image.style(:product)&.dig(:url)
    return if path.blank?
    return path if path.start_with?('http')

    base = admin_base_url
    base && "#{base}#{path}"
  rescue StandardError
    nil
  end

  def admin_base_url
    options = (Rails.application.routes.default_url_options || {}).symbolize_keys
    host = options[:host].to_s
    return if host.blank?
    return host.chomp('/') if host.match?(%r{\Ahttps?://})

    protocol = (options[:protocol].presence || 'http').to_s.delete_suffix('://')
    port = options[:port].present? ? ":#{options[:port]}" : ''
    "#{protocol}://#{host}#{port}"
  end
end
