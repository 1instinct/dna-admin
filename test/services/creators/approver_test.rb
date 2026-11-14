require 'test_helper'

class Creators::ApproverTest < ActiveSupport::TestCase
  setup do
    @admin = admin_user
    @application = create(:creator_application)
    @user = @application.user
  end

  test 'approve creates account, adds creator role and records the review' do
    account = Creators::Approver.approve!(@application, @admin, 'Welcome')

    assert_equal @user.id, account.user_id
    assert_equal 7000, account.revenue_share_bps
    assert_equal 'active', account.status
    assert @user.reload.has_spree_role?('creator')
    assert Creators.creator?(@user)
    @application.reload
    assert_equal 'approved', @application.status
    assert_equal @admin.id, @application.reviewed_by_id
    assert_equal 'Welcome', @application.review_note
    assert @application.reviewed_at
  end

  test 'approve sets is_creator when column exists' do
    with_user_column(:is_creator) do
      Creators::Approver.approve!(@application, @admin)
      assert_equal true, Spree::User.find(@user.id).is_creator

      Creators::Approver.revoke!(@user)
      assert_equal false, Spree::User.find(@user.id).is_creator
    end
  end

  test 'approve works without an is_creator column' do
    refute Spree::User.column_names.include?('is_creator')
    Creators::Approver.approve!(@application, @admin)
    assert Creators.creator?(@user.reload)
  end

  test 'approve uses the configured default share' do
    Creators.config.default_share_bps = 6500
    assert_equal 6500, Creators::Approver.approve!(@application, @admin).revenue_share_bps
  ensure
    Creators.reset_config!
  end

  test 'approving twice keeps one account and one role' do
    Creators::Approver.approve!(@application, @admin)
    assert_raises(Spree::CreatorApplication::NotPending) { Creators::Approver.approve!(@application.reload, @admin) }
    assert_equal 1, Spree::CreatorAccount.where(user_id: @user.id).count
    assert_equal 1, @user.reload.spree_roles.where(name: 'creator').count
  end

  test 'reject stores the note and grants nothing' do
    Creators::Approver.reject!(@application, @admin, 'Not yet')
    assert_equal 'rejected', @application.reload.status
    assert_equal 'Not yet', @application.review_note
    refute Creators.creator?(@user.reload)
    assert_nil Spree::CreatorAccount.find_by(user_id: @user.id)
  end

  test 'revoke removes role and suspends the account' do
    account = Creators::Approver.approve!(@application, @admin)
    Creators::Approver.revoke!(@user)

    refute @user.reload.has_spree_role?('creator')
    refute Creators.creator?(@user)
    assert_equal 'suspended', account.reload.status
  end

  test 're-approving a revoked creator reactivates the same account' do
    account = Creators::Approver.approve!(@application, @admin)
    Creators::Approver.revoke!(@user)
    again = create(:creator_application, user: @user)
    assert_equal account.id, Creators::Approver.approve!(again, @admin).id
    assert_equal 'active', account.reload.status
  end

  test 'the profile reports is_creator from the role' do
    profile = @user.profile || @user.create_profile!
    profile.update!(handle: 'nightshift')
    refute Profiles::Presenter.new(profile.reload).own_json[:is_creator]

    Creators::Approver.approve!(@application, @admin)
    assert Profiles::Presenter.new(profile.reload).own_json[:is_creator]
  end
end
