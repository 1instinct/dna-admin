class Contact < ApplicationRecord
  has_many :sent_messages, class_name: 'Message',as: :sender, dependent: :destroy
  has_many :received_messages, class_name: 'Message', as: :receiver, dependent: :destroy
  belongs_to :actor, class_name: 'Spree::User'
end
