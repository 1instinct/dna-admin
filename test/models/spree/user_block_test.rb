require 'test_helper'

class Spree::UserBlockTest < ActiveSupport::TestCase
  setup do
    @a = create(:user)
    @b = create(:user)
  end

  test 'creating a block removes follows both ways' do
    UserFollow.create!(follower: @a, following: @b)
    UserFollow.create!(follower: @b, following: @a)
    other = create(:user)
    kept = UserFollow.create!(follower: @a, following: other)

    Spree::UserBlock.block!(@a, @b)

    assert_equal 0, UserFollow.where(follower_id: [@a.id, @b.id], following_id: [@a.id, @b.id]).count
    assert UserFollow.exists?(kept.id)
  end

  test 'block! is idempotent' do
    first = Spree::UserBlock.block!(@a, @b)
    second = Spree::UserBlock.block!(@a, @b)
    assert_equal first, second
    assert_equal 1, Spree::UserBlock.count
  end

  test 'cannot block yourself' do
    refute Spree::UserBlock.new(blocker: @a, blocked: @a).valid?
  end

  test 'between? checks either direction' do
    refute Spree::UserBlock.between?(@a, @b)
    Spree::UserBlock.block!(@a, @b)
    assert Spree::UserBlock.between?(@a, @b)
    assert Spree::UserBlock.between?(@b, @a)
    refute Spree::UserBlock.between?(@a, nil)
  end

  test 'user helpers' do
    Spree::UserBlock.block!(@a, @b)
    assert @a.blocking?(@b)
    refute @b.blocking?(@a)
    assert @b.blocked_with?(@a)
  end
end
