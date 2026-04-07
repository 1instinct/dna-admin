class Contact < Spree::Base
  has_many :sent_messages, class_name: 'Message',as: :sender, dependent: :destroy
  has_many :received_messages, class_name: 'Message', as: :receiver, dependent: :destroy
  belongs_to :actor, class_name: 'Spree::User'

  self.whitelisted_ransackable_attributes = %w[id full_name email]
  self.whitelisted_ransackable_scopes = %w[search_contact]
  def self.search_contact(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:email).where("LOWER(#{Contact.table_name}.email) LIKE LOWER(:query) OR LOWER(full_name) LIKE LOWER(:query)", query: "%#{query}%").distinct
    else
      where("LOWER(#{Contact.table_name}.email) LIKE LOWER(:query) OR LOWER(full_name) LIKE LOWER(:query)", query: "%#{query}%")
    end
  end
end
