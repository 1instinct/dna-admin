module Spree
  # Admin actions on in-app purchases (manual revocations), with the admin's note.
  class IapAuditLog < Spree::Base
    belongs_to :iap_transaction, class_name: 'Spree::IapTransaction'
    belongs_to :admin_user, class_name: Spree.user_class.to_s, optional: true

    validates :action, presence: true
    validates :note, presence: true
  end
end
