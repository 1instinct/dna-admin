require 'test_helper'

# AccountDeletion removes the user's push subscriptions, so a deleted account's devices get no
# more notifications; other users' devices stay subscribed.
class AccountDeletionPushSubscriptionsTest < ActiveSupport::TestCase
  test "the user's push subscriptions are deleted" do
    user = create(:user)
    other = create(:user)
    PushSubscription.create!(user: user, token: 'ExponentPushToken[mine]', platform: 'ios')
    theirs = PushSubscription.create!(user: other, token: 'ExponentPushToken[theirs]', platform: 'android')

    assert AccountDeletion.call(user)

    assert_empty PushSubscription.where(user_id: user.id)
    assert PushSubscription.exists?(theirs.id)
  end
end
