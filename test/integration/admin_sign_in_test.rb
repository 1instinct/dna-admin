require 'test_helper'

# The signed-out gate (ApplicationController#require_login) and the password
# pages it lets through. The gate used to render a bare partial with no <head>,
# so phones got no viewport and laid the form out at desktop width.
class AdminSignInTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear # Spree caches the default store across tests
    unless Spree::Store.default.persisted?
      Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "sign-in-#{SecureRandom.hex(3)}",
                           mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
    end
    @admin = create(:user, email: 'admin@example.com', password: 'secret123', password_confirmation: 'secret123')
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
  end

  test 'a signed-out admin page renders a full, mobile-ready sign-in document' do
    get '/admin/orders'

    assert_response :success
    assert_match(/\A\s*<!DOCTYPE html>/i, response.body)
    assert_select 'meta[name=viewport][content*="width=device-width"]'
    assert_select 'title', /Login|Sign in/i
    assert_select 'form[action="/login"][method=post]' do
      assert_select 'input[type=email][name="spree_user[email]"][autocomplete=username][autocapitalize=none]'
      assert_select 'input[type=password][name="spree_user[password]"][autocomplete=current-password]'
      assert_select 'label[for=spree_user_email]'
      assert_select 'label[for=spree_user_password]'
      assert_select 'button[type=submit]'
    end
    assert_select 'a[href="/password/recover"]'
  end

  test 'a wrong password says so and keeps the email' do
    post '/login', params: { spree_user: { email: 'admin@example.com', password: 'nope' } }

    assert_response :success
    assert_select '.si-alert--error[role=alert]', /invalid/i
    assert_select 'input[name="spree_user[email]"][value="admin@example.com"]'
  end

  test 'signing in from the gate returns to the page that was asked for' do
    get '/admin/products?q=widget'
    post '/login', params: { spree_user: { email: 'admin@example.com', password: 'secret123' } }

    assert_redirected_to '/admin/products?q=widget'
  end

  test 'signing in with no page to return to lands an admin on the admin' do
    post '/login', params: { spree_user: { email: 'admin@example.com', password: 'secret123' } }

    assert_redirected_to '/admin'
  end

  test 'forgot password is reachable while signed out' do
    get '/password/recover'

    assert_response :success
    assert_select 'meta[name=viewport]'
    assert_select 'form[action="/password/recover"] input[name="spree_user[email]"]'
    assert_select 'form[action="/login"]', count: 0
  end

  test 'requesting a reset sends the email and returns to sign in' do
    assert_emails 1 do
      post '/password/recover', params: { spree_user: { email: 'admin@example.com' } }
    end
    assert_redirected_to '/login'
  end

  test 'with ADMIN_URL set, the reset email links to the admin' do
    with_env('ADMIN_URL' => 'https://admin.example.com') do
      post '/password/recover', params: { spree_user: { email: 'admin@example.com' } }
    end

    body = ActionMailer::Base.deliveries.last.body.encoded
    assert_match %r{https://admin\.example\.com/user/spree_user/password/edit\?reset_password_token=}, body
  end

  test 'without ADMIN_URL, the reset email keeps the store URL' do
    with_env('ADMIN_URL' => nil) do
      post '/password/recover', params: { spree_user: { email: 'admin@example.com' } }
    end

    assert_match %r{test\.example\.com/user/spree_user/password/edit}, ActionMailer::Base.deliveries.last.body.encoded
  end

  test 'a forged Host header does not change the reset link' do
    with_env('ADMIN_URL' => 'https://admin.example.com') do
      post '/password/recover', params: { spree_user: { email: 'admin@example.com' } },
                                headers: { 'Host' => 'evil.example.net' }
    end

    assert_no_match(/evil\.example\.net/, ActionMailer::Base.deliveries.last.body.encoded)
  end

  test 'phones get the small copy of the default background' do
    with_env('COMPANY_BACKGROUND' => nil, 'COMPANY_BACKGROUND_MOBILE' => nil) { get '/admin/orders' }

    assert_match %r{url\("[^"]*/background-mobile[^"]*\.jpg"\)}, response.body
    assert_match %r{url\("[^"]*/background(-[0-9a-f]+)?\.jpg"\)}, response.body
  end

  test 'COMPANY_BACKGROUND_MOBILE names the phone copy, and a custom background without one is used as is' do
    with_env('COMPANY_BACKGROUND' => 'instinct_logo.png', 'COMPANY_BACKGROUND_MOBILE' => nil) { get '/admin/orders' }
    assert_no_match(/background-mobile/, response.body)

    with_env('COMPANY_BACKGROUND' => 'instinct_logo.png', 'COMPANY_BACKGROUND_MOBILE' => 'background-mobile.jpg') { get '/admin/orders' }
    assert_match(/background-mobile[^"]*\.jpg/, response.body)
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  test 'a signed-out JSON request gets a 401, not the sign-in page' do
    get '/admin/orders', headers: { 'Accept' => 'application/json' }

    assert_response :unauthorized
  end

  test 'a signed-out XHR gets a 401' do
    get '/admin/orders', xhr: true

    assert_response :unauthorized
  end

  test 'a signed-out request accepting anything still gets the sign-in page' do
    get '/admin/orders', headers: { 'Accept' => '*/*' }

    assert_response :success
    assert_select 'form[action="/login"]'
  end
end
