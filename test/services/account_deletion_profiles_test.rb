require 'test_helper'

# AccountDeletion covers the profiles module: profile + avatar, blocks both ways, reports about
# the user's profile (deleted) and reports by the user (kept, reporter_id nulled).
class AccountDeletionProfilesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:user)
    @profile = create(:user_profile, user: @user, handle: 'leaver')
    @other = create(:user)
    @other_profile = create(:user_profile, user: @other, handle: 'stayer')
  end

  test 'profile row is destroyed and the avatar purge is enqueued' do
    @profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    blob_id = @profile.avatar.blob.id

    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      AccountDeletion.call(@user)
    end
    refute Spree::UserProfile.exists?(@profile.id)
    refute ActiveStorage::Attachment.where(record_type: 'Spree::UserProfile', record_id: @profile.id).exists?
    perform_enqueued_jobs
    refute ActiveStorage::Blob.exists?(blob_id)
  end

  test 'the handle is free again afterwards' do
    AccountDeletion.call(@user)
    assert create(:user_profile, handle: 'leaver').persisted?
  end

  test 'blocks both ways are deleted, others kept' do
    Spree::UserBlock.block!(@user, @other)
    Spree::UserBlock.block!(@other, @user)
    third = create(:user)
    kept = Spree::UserBlock.block!(@other, third)

    AccountDeletion.call(@user)

    assert_equal [kept.id], Spree::UserBlock.pluck(:id)
  end

  test 'reports about the profile are deleted; reports by the user are kept with reporter_id nil' do
    about = Spree::ContentReport.for_profile(@profile, reporter: @other, reason: 'spam')
    about.save!
    by = Spree::ContentReport.for_profile(@other_profile, reporter: @user, reason: 'hate')
    by.save!

    AccountDeletion.call(@user)

    refute Spree::ContentReport.exists?(about.id)
    assert Spree::ContentReport.exists?(by.id)
    assert_nil by.reload.reporter_id
    assert_equal 'stayer', by.snapshot['handle']
  end

  test 'a user without a profile deletes cleanly' do
    user = create(:user)
    assert AccountDeletion.call(user)
  end
end
