require 'test_helper'

# AccountDeletion removes the user's tracks and purges their audio; other users' tracks stay.
class AccountDeletionUserTracksTest < ActiveSupport::TestCase
  setup { setup_user_tracks }
  teardown { reset_user_tracks! }

  test "the user's tracks and their audio are deleted" do
    user = create(:user)
    mine = create_user_track(user)
    mine.audio.attach(io: StringIO.new('fLaC'), filename: 'loop.flac', content_type: 'audio/flac')
    blob = mine.audio.blob
    theirs = create_user_track(create(:user))

    assert AccountDeletion.call(user)

    refute Spree::UserTrack.exists?(mine.id)
    refute ActiveStorage::Blob.exists?(blob.id)
    assert Spree::UserTrack.exists?(theirs.id)
  end
end
