module Creators
  # Reviews creator applications and grants or removes the creator role.
  #
  # - approve!: the application becomes approved; the user gets a creator account (an existing,
  #   suspended one is reactivated), the creator role, and is_creator = true when users have that
  #   column.
  # - reject!: the application becomes rejected with the note; nothing is granted.
  # - revoke!: removes the role (and is_creator) and suspends the account. The account, its
  #   earnings and payouts are kept.
  module Approver
    module_function

    def approve!(application, reviewer, note = nil)
      Spree::CreatorApplication.transaction do
        application.lock!
        raise Spree::CreatorApplication::NotPending, 'Only a pending application can be approved' unless application.pending?

        application.update!(status: 'approved', reviewed_by: reviewer, reviewed_at: Time.current,
                            review_note: note.to_s.strip.presence)
        user = application.user
        account = Spree::CreatorAccount.lock.find_or_initialize_by(user_id: user.id)
        account.status = 'active'
        account.save!
        user.spree_roles << Creators.role unless user.spree_roles.exists?(name: Creators.config.role_name)
        sync_flag(user, true)
        account
      end
    end

    def reject!(application, reviewer, note = nil)
      Spree::CreatorApplication.transaction do
        application.lock!
        raise Spree::CreatorApplication::NotPending, 'Only a pending application can be rejected' unless application.pending?

        application.update!(status: 'rejected', reviewed_by: reviewer, reviewed_at: Time.current,
                            review_note: note.to_s.strip.presence)
        application
      end
    end

    def revoke!(user)
      Spree::CreatorApplication.transaction do
        role_ids = Spree::Role.where(name: Creators.config.role_name).pluck(:id)
        Spree::RoleUser.where(user_id: user.id, role_id: role_ids).delete_all if role_ids.any?
        user.spree_roles.reset
        Spree::CreatorAccount.where(user_id: user.id).find_each { |account| account.update!(status: 'suspended') }
        sync_flag(user, false)
      end
      user
    end

    # Keeps users.is_creator in step with the role, when the column exists.
    def sync_flag(user, value)
      return unless Spree.user_class.column_names.include?('is_creator')

      Spree.user_class.where(id: user.id).update_all(is_creator: value, updated_at: Time.current)
    end
  end
end
