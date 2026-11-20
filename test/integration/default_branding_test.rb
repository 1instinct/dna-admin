require 'test_helper'

# The ENV.fetch fallbacks in the login, forbidden and unauthorized views are only live in production:
# config/initializers/dotenv.rb requires COMPANY_LOGO and COMPANY_BACKGROUND in development and test.
# These tests remove the keys so the fallbacks are what renders, and assert that the fallback is the
# neutral boilerplate asset and that the asset exists.
class DefaultBrandingTest < ActionDispatch::IntegrationTest
  test 'the neutral default assets exist' do
    %w[instinct_logo.png background.jpg].each do |name|
      assert Rails.root.join('app/assets/images', name).file?, "app/assets/images/#{name} is missing"
    end
  end

  test 'the admin login falls back to the neutral logo and background' do
    html = without_branding_env { get('/admin/login'); response.body }

    assert_response :ok
    assert_match %r{<img[^>]+src="[^"]*instinct_logo[^"]*\.png"}, html
    assert_match %r{url\("[^"]*background[^"]*\.jpg"\)}, html
    assert_no_match(/beeper/i, html)
  end

  test 'the forbidden and unauthorized pages fall back to the neutral background' do
    %w[/forbidden /unauthorized].each do |path|
      html = without_branding_env { get(path); response.body }

      assert_match %r{url\("[^"]*background[^"]*\.jpg"\)}, html, path
      assert_no_match(/beeper/i, html, path)
    end
  end

  private

  def without_branding_env
    saved = ENV.to_h.slice('COMPANY_LOGO', 'COMPANY_BACKGROUND')
    saved.each_key { |k| ENV.delete(k) }
    yield
  ensure
    ENV.update(saved)
  end
end
