require 'test_helper'

# Affiliates.config: where affiliate links point and the visitor hash salt.
class AffiliatesConfigTest < ActiveSupport::TestCase
  def with_env(values)
    saved = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test 'links point at AFFILIATE_LINK_BASE_URL, else SITE_URL, without a trailing slash' do
    with_env('AFFILIATE_LINK_BASE_URL' => 'https://shop.example.com/', 'SITE_URL' => 'https://www.example.com') do
      assert_equal 'https://shop.example.com', Affiliates::Config.new.link_base_url
    end
    with_env('AFFILIATE_LINK_BASE_URL' => nil, 'SITE_URL' => 'https://www.example.com/') do
      assert_equal 'https://www.example.com', Affiliates::Config.new.link_base_url
    end
  end

  test 'a configured link base wins over the environment' do
    with_env('AFFILIATE_LINK_BASE_URL' => 'https://shop.example.com') do
      config = Affiliates::Config.new
      config.link_base_url = 'https://other.example.com/'
      assert_equal 'https://other.example.com', config.link_base_url
    end
  end

  test 'the visitor salt comes from AFFILIATE_VISITOR_SALT, else from secret_key_base' do
    with_env('AFFILIATE_VISITOR_SALT' => 'fixed-salt') do
      assert_equal 'fixed-salt', Affiliates::Config.new.visitor_salt
    end
    with_env('AFFILIATE_VISITOR_SALT' => nil) do
      derived = Affiliates::Config.new.visitor_salt
      assert_equal 64, derived.length
      assert_equal derived, Affiliates::Config.new.visitor_salt
    end
  end
end
