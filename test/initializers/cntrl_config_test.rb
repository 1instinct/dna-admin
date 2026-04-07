require "test_helper"

class CntrlConfigTest < ActiveSupport::TestCase
  test "starter kit bundle NDC is configured" do
    config = Rails.application.config.cntrl
    assert_equal "02400000713", config.starter_kit["bundle_ndc"]
  end

  test "starter kit device NDCs are configured" do
    config = Rails.application.config.cntrl
    assert_equal 3, config.starter_kit["device_ndcs"].length
    assert_includes config.starter_kit["device_ndcs"], "02400000714"
  end

  test "dedup window is configured" do
    config = Rails.application.config.cntrl
    assert_equal 10, config.starter_kit["dedup_window_minutes"]
  end
end
