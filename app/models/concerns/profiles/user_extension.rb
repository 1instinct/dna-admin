module Profiles
  # Profile, block and lock support on the user model (included from config/initializers/profiles.rb).
  module UserExtension
    extend ActiveSupport::Concern

    included do
      has_one :profile, class_name: 'Spree::UserProfile', foreign_key: :user_id, inverse_of: :user, dependent: :destroy
      has_many :blocks_made, class_name: 'Spree::UserBlock', foreign_key: :blocker_id, dependent: :delete_all
      has_many :blocks_received, class_name: 'Spree::UserBlock', foreign_key: :blocked_id, dependent: :delete_all

      prepend Locking
    end

    # self blocked other.
    def blocking?(other)
      return false unless other&.id

      Spree::UserBlock.where(blocker_id: id, blocked_id: other.id).exists?
    end

    # A block exists between self and other, either way.
    def blocked_with?(other)
      Spree::UserBlock.between?(self, other)
    end

    def account_locked?
      respond_to?(:locked_at) && locked_at.present?
    end

    # Moderators lock an account by setting locked_at (Devise's column). A locked account can't
    # sign in with a password (session or OAuth password grant).
    module Locking
      def active_for_authentication?
        super && !account_locked?
      end

      def valid_for_authentication?
        return false if account_locked?

        super
      end

      def inactive_message
        account_locked? ? :locked : super
      end
    end
  end
end
