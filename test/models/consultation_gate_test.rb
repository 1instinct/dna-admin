require "test_helper"

class ConsultationGateTest < ActiveSupport::TestCase
  setup do
    # Ensure Product has requires_consultation column loaded
    Spree::Product.reset_column_information unless Spree::Product.column_names.include?("requires_consultation")
    @product = Spree::Product.new(name: "Test Product", price: 10.0)
    @user_passed = Spree::User.new(
      email: "passed@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @user_passed.consultation_status = :pass

    @user_none = Spree::User.new(
      email: "none@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "non-consultation product can be purchased by anyone" do
    @product.requires_consultation = false
    assert @product.can_purchase?(nil)
    assert @product.can_purchase?(@user_none)
    assert @product.can_purchase?(@user_passed)
  end

  test "consultation product cannot be purchased without user" do
    @product.requires_consultation = true
    assert_not @product.can_purchase?(nil)
  end

  test "consultation product cannot be purchased without passing" do
    @product.requires_consultation = true
    assert_not @product.can_purchase?(@user_none)
  end

  test "consultation product can be purchased after passing" do
    @product.requires_consultation = true
    assert @product.can_purchase?(@user_passed)
  end
end
