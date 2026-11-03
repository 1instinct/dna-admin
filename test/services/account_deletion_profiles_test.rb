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

  test 'profile row and avatar are removed before the call returns, with no job left to lose' do
    @profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    blob = @profile.avatar.blob
    clear_enqueued_jobs

    assert_no_enqueued_jobs { AccountDeletion.call(@user) }

    refute Spree::UserProfile.exists?(@profile.id)
    refute ActiveStorage::Attachment.where(record_type: 'Spree::UserProfile', record_id: @profile.id).exists?
    refute ActiveStorage::Blob.exists?(blob.id)
    refute blob.service.exist?(blob.key), 'the stored file is gone'
  end

  test 'a failed purge does not fail the deletion and logs no personal data' do
    @profile.avatar.attach(fixture_upload('avatar.png', 'image/png'))
    key = @profile.avatar.blob.key
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    ActiveStorage::Blob.class_eval do
      alias_method :__purge, :purge
      define_method(:purge) { raise IOError, 'storage down' }
    end

    assert AccountDeletion.call(@user)

    refute Spree::UserProfile.exists?(@profile.id)
    assert_includes io.string, 'avatar purge failed: IOError'
    assert_includes io.string, "blob_key=#{key}", 'so the orphaned file can be traced'
    refute_includes io.string, @user.email
  ensure
    Rails.logger = old_logger
    ActiveStorage::Blob.class_eval do
      alias_method :purge, :__purge
      remove_method :__purge
    end
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

  test 'reports about the profile are deleted; reports by the user keep the target but lose reporter and details' do
    about = Spree::ContentReport.for_profile(@profile, reporter: @other, reason: 'spam')
    about.save!
    by = Spree::ContentReport.for_profile(@other_profile, reporter: @user, reason: 'hate', details: 'call me on 555')
    by.save!

    AccountDeletion.call(@user)

    refute Spree::ContentReport.exists?(about.id)
    assert Spree::ContentReport.exists?(by.id)
    assert_nil by.reload.reporter_id
    assert_nil by.details, 'free text can hold personal data'
    assert_equal 'hate', by.reason
    assert_equal 'stayer', by.snapshot['handle']
  end

  test 'a user without a profile deletes cleanly' do
    user = create(:user)
    assert AccountDeletion.call(user)
  end
end
