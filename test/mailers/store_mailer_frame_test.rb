require 'test_helper'
require 'minitest/mock'

# The shared email frame (shared/_email_frame): review emails and Spree's own emails get the
# background, logo badge, card, dark mode and copyright footer.
class StoreMailerFrameTest < ActionMailer::TestCase
  setup do
    @url_options = Rails.application.routes.default_url_options.dup
    reviews_enable!
    review_requests_home!
    @store = @review_requests_store
    @store.update!(name: 'DNA', address: '1 Mercer St, New York', customer_support_email: 'help@dna.example', instagram: '@dna')
    @order = review_requests_order(media_product(name: 'Wrap Top'), user: create(:user)).reload
    @request = Spree::ReviewRequest.create!(order: @order, email: @order.email, status: 'sent', send_after: Time.current,
                                            expires_at: 60.days.from_now)
  end

  teardown { Rails.application.routes.default_url_options.replace(@url_options) }

  def html(mail)
    (mail.html_part || mail).body.to_s
  end

  test 'review emails get the frame: footer, copyright, dark mode, store name as the badge' do
    body = html(ReviewRequestMailer.request_review(@request, 'tok'))
    assert_includes body, 'class="em-bg"'
    assert_includes body, 'prefers-color-scheme: dark'
    scheme = EmailTheme.always_dark? ? 'dark' : 'light dark'
    assert_includes body, %(<meta name="color-scheme" content="#{scheme}" />)
    assert_includes body, "© #{Time.current.year} DNA. All rights reserved."
    assert_includes body, '1 Mercer St, New York'
    assert_includes body, 'mailto:help@dna.example'
    assert_includes body, 'https://instagram.com/dna'
    assert_includes body, 'Stop review emails'
    if EmailTheme.current[:default_logo].blank?
      assert_includes body, 'letter-spacing:4px', 'no logo uploaded and no theme default: the store name stands in'
    end

    text = ReviewRequestMailer.request_review(@request, 'tok').text_part.body.to_s
    assert_includes text, "© #{Time.current.year} DNA. All rights reserved."
  end

  test 'with a public address, the logo and background images are absolute URLs' do
    Rails.application.routes.default_url_options.merge!(host: 'admin.example.com', protocol: 'https')
    @store.mailer_logo.attach(io: StringIO.new(ShopMediaTestHelper::PNG_BYTES), filename: 'logo.png', content_type: 'image/png')
    body = html(ReviewRequestMailer.request_review(@request, 'tok'))
    assert_includes body, "background-image:url('https://admin.example.com/email/pattern-light.png')"
    assert_includes body, "url('https://admin.example.com/email/pattern-dark.png')"
    assert_match %r{<img alt="DNA"[^>]+src="https://admin\.example\.com/rails/active_storage/}, body
  end

  test 'without a public address, images are left out instead of broken' do
    Rails.application.routes.default_url_options.delete(:host)
    body = html(ReviewRequestMailer.request_review(@request, 'tok'))
    refute_includes body, 'pattern-light.png'
    refute_match %r{src="/}, body
  end

  test "Spree's order emails use the same frame" do
    body = html(Spree::OrderMailer.confirm_email(@order))
    assert_includes body, 'class="em-bg"'
    assert_includes body, "© #{Time.current.year} DNA. All rights reserved."
    assert_includes body, @order.number
  end

  test "a store's config/email_theme.yml changes colors, tiles, scheme and the default logo" do
    custom = { 'color_scheme' => 'dark', 'page_bg' => '#0a0020', 'card_bg' => '#140a2e', 'accent' => '#00ffff',
               'pattern' => '/email/store-tile.png', 'default_logo' => '/email/store-logo.png' }
    Rails.application.routes.default_url_options.merge!(host: 'admin.example.com', protocol: 'https')
    EmailTheme.stub(:current, EmailTheme::DEFAULTS.merge(custom.symbolize_keys)) do
      body = html(ReviewRequestMailer.request_review(@request, 'tok'))
      assert_includes body, '<meta name="color-scheme" content="dark" />'
      assert_includes body, 'background-color:#0a0020'
      assert_includes body, 'background-color:#140a2e'
      assert_includes body, 'color:#00ffff', 'stars use the accent'
      assert_includes body, "url('https://admin.example.com/email/store-tile.png')"
      assert_includes body, 'src="https://admin.example.com/email/store-logo.png"', 'no store logo uploaded: the theme default'
    end
  end

  test 'missing theme keys fall back to the defaults' do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join('email_theme.yml')
      path.write(%(accent: "#123456"\n))
      theme = EmailTheme.load_file(path)
      assert_equal EmailTheme::DEFAULTS.keys.sort, theme.keys.sort
      assert_equal '#123456', theme[:accent]
      assert_equal EmailTheme::DEFAULTS[:card_bg], theme[:card_bg]
    end
  end
end
