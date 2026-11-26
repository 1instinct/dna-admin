require 'test_helper'

# M4.2: the review request email and its reminder.
class ReviewRequestMailerTest < ActionMailer::TestCase
  setup do
    reviews_enable!
    review_requests_home!
    @top = media_product(name: 'Wrap Top')
    @skirt = media_product(name: 'Slip Skirt')
    media_image(@top.master, ShopMediaTestHelper::PNG_BYTES, 'top.png', 'image/png', width: 1, height: 1)
    @order = review_requests_order(@top, @skirt, email: 'maya@example.com')
    @request, @token = review_request_for(@order)
    @lines = @order.line_items.index_by { |li| li.variant.product_id }
  end

  def site
    SITE_URL.to_s.chomp('/')
  end

  test 'one row of five star links per item, an opt-out link, neutral copy' do
    mail = ReviewRequestMailer.request_review(@request, @token)
    assert_equal ['maya@example.com'], mail.to
    assert_equal ['store@example.com'], mail.from
    assert_equal "How's your Test Store order?", mail.subject

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    [@top, @skirt].each do |product|
      line_item = @lines.fetch(product.id)
      (1..5).each do |rating|
        url = "#{site}/review/#{@token}?item=#{line_item.id}&rating=#{rating}"
        assert_includes html, %(href="#{url.gsub('&', '&amp;')}"), "#{product.name} #{rating}"
        assert_includes html, %(aria-label="Rate #{product.name} #{rating} out of 5")
        assert_includes text, url
      end
      assert_includes html, product.name
    end
    opt_out = "#{site}/review/#{@token}?opt_out=1"
    assert_includes html, %(href="#{opt_out}")
    assert_includes text, opt_out
    assert_includes html, 'Tap a star to rate each piece'
    assert_match %r{<img src="http://localhost/rails/active_storage/representations/[^"]+" width="88"}, html,
                 'product images use absolute URLs'
    assert_includes text, 'Members earn 50 points for every review, plus 50 with a photo, whatever the rating.'
    refute_match(/love|positive|5.star review/i, html + text)
  end

  test 'the raw token is in the email but not stored' do
    mail = ReviewRequestMailer.request_review(@request, @token)
    assert_includes mail.html_part.body.to_s, @token
    @request.reload
    refute_includes @request.attributes.values.map(&:to_s), @token
    assert_equal Spree::ReviewRequest.digest(@token), @request.token_digest
  end

  test 'items already reviewed are left out; no points line when points are off' do
    reviews_enable!(points_per_review: 0)
    reviews_submit(@top, review_request: @request, rating: 3)
    mail = ReviewRequestMailer.request_review(@request, @token)
    html = mail.html_part.body.to_s
    refute_includes html, "item=#{@lines.fetch(@top.id).id}&"
    assert_includes html, "item=#{@lines.fetch(@skirt.id).id}&amp;rating=1"
    refute_includes html, 'points'
  end

  test 'reminder' do
    mail = ReviewRequestMailer.reminder(@request, @token)
    assert_equal "Reminder: how's your Test Store order?", mail.subject
    assert_includes mail.text_part.body.to_s, "You can still rate the pieces from order #{@order.number}."
    assert_includes mail.html_part.body.to_s, "#{site}/review/#{@token}?opt_out=1"
  end
end
