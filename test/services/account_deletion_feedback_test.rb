require 'test_helper'

# AccountDeletion removes the feedback a user sent, with its screenshots; anonymous feedback and
# other users' feedback stay.
class AccountDeletionFeedbackTest < ActiveSupport::TestCase
  test "the user's feedback and screenshots are deleted" do
    user = create(:user)
    mine = create(:app_feedback, user: user)
    mine.screenshot.attach(fixture_upload('avatar.png', 'image/png'))
    blob = mine.screenshot.blob
    theirs = create(:app_feedback, user: create(:user))
    anonymous = create(:app_feedback)

    assert AccountDeletion.call(user)

    refute AppFeedback.exists?(mine.id)
    refute ActiveStorage::Attachment.where(record_type: 'AppFeedback', record_id: mine.id).exists?
    refute ActiveStorage::Blob.exists?(blob.id)
    assert AppFeedback.exists?(theirs.id)
    assert AppFeedback.exists?(anonymous.id)
  end
end
