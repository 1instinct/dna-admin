require "test_helper"

class SpreeUserConsultationTest < ActiveSupport::TestCase
  setup do
    @user = Spree::User.new(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "consultation_status defaults to none" do
    assert_equal "none", @user.consultation_status
  end

  test "consultation_passed? returns true when status is pass" do
    @user.consultation_status = :pass
    assert @user.consultation_passed?
  end

  test "consultation_passed? returns false when status is none" do
    assert_not @user.consultation_passed?
  end

  test "consultation_passed? returns false when status is fail" do
    @user.consultation_status = :fail
    assert_not @user.consultation_passed?
  end

  test "consultation_pending? returns true when status is pending" do
    @user.consultation_status = :pending
    assert @user.consultation_pending?
  end

  test "valid consultation_status values" do
    %w[none pending pass fail].each do |status|
      @user.consultation_status = status
      assert @user.valid?, "Expected #{status} to be valid"
    end
  end
end
