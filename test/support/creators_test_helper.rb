# Shared helpers for the creators module tests.
module CreatorsTestHelper
  # A user with the creator role and an active creator account.
  def creator_user(handle: nil, name: nil)
    user = create(:user)
    Creators::Approver.approve!(create(:creator_application, user: user), create(:user))
    if handle || name
      profile = user.profile || user.create_profile!
      profile.update!(handle: handle, name: name)
    end
    user.reload
  end

  def admin_user
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  # Runs the block with a temporary boolean column on spree_users. Postgres DDL is transactional,
  # and the column is dropped again before the test's transaction rolls back.
  def with_user_column(name)
    connection = ActiveRecord::Base.connection
    connection.add_column :spree_users, name, :boolean, default: false, null: false
    connection.clear_cache!
    Spree::User.reset_column_information
    yield
  ensure
    connection.remove_column :spree_users, name if connection.column_exists?(:spree_users, name)
    connection.clear_cache!
    Spree::User.reset_column_information
  end
end

ActiveSupport::TestCase.include(CreatorsTestHelper)
