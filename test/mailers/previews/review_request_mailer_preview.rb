# Preview at /rails/mailers/review_request_mailer (development). Uses the newest order that has
# shipped items to review, and an unsaved request so previewing never changes data.
class ReviewRequestMailerPreview < ActionMailer::Preview
  def request_review
    ReviewRequestMailer.request_review(preview_request, 'preview-token')
  end

  def reminder
    ReviewRequestMailer.reminder(preview_request, 'preview-token')
  end

  private

  def preview_request
    order = Reviews::Eligibility.shipped_line_items.order('spree_orders.completed_at DESC').first&.order
    raise 'Ship an order first: the preview needs an order with shipped items.' unless order

    Spree::ReviewRequest.new(order: order, email: order.email, status: 'sent', send_after: Time.current,
                             expires_at: 60.days.from_now)
  end
end
