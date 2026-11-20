require 'test_helper'

class UserTracks::QuotaTest < ActiveSupport::TestCase
  setup do
    setup_user_tracks(monthly_free: 3)
    @user = create(:user)
  end

  teardown { reset_user_tracks! }

  test 'each track this month uses a credit; refunded ones and last month do not' do
    assert_equal 3, UserTracks::Quota.remaining(@user)
    create_user_track(@user)
    assert_equal 2, UserTracks::Quota.remaining(@user)

    refunded = create_user_track(@user)
    assert UserTracks::Quota.refund!(refunded)
    assert_equal 2, UserTracks::Quota.remaining(@user)

    create_user_track(@user, created_at: 40.days.ago)
    create_user_track(create(:user))
    assert_equal 2, UserTracks::Quota.remaining(@user)
  end

  test 'a deleted track still used its credit' do
    track = create_user_track(@user)
    UserTracks::Removal.call(track)
    assert_equal 2, UserTracks::Quota.remaining(@user)
  end

  test 'refund! is idempotent' do
    track = create_user_track(@user)
    assert UserTracks::Quota.refund!(track)
    stamp = track.reload.credit_refunded_at
    refute UserTracks::Quota.refund!(Spree::UserTrack.find(track.id))
    assert_equal stamp, track.reload.credit_refunded_at
    assert_equal 3, UserTracks::Quota.remaining(@user)
  end

  test 'debit! saves the track while a credit is left, and refuses past the quota' do
    3.times { UserTracks::Quota.debit!(Spree::UserTrack.new(user: @user, request: track_request, title: 't')) }
    assert_equal 0, UserTracks::Quota.remaining(@user)
    track = Spree::UserTrack.new(user: @user, request: track_request, title: 't')
    assert_raises(UserTracks::Quota::Exhausted) { UserTracks::Quota.debit!(track) }
    refute track.persisted?
  end

  test 'remaining never goes below zero' do
    UserTracks.config.monthly_free = 1
    2.times { create_user_track(@user) }
    assert_equal 0, UserTracks::Quota.remaining(@user)
  end
end
