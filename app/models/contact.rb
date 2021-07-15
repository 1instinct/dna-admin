class Contact < ApplicationRecord  
  # serialize :phone, Array
  # serialize :ip

  # validates :phone, array: { uniqueness: { scope: :actor_id, message: :uniqueness }, if: proc { |f| f.phone.present? } }
  # validates :email, array: { uniqueness: { scope: :actor_id, message: :uniqueness }, if: proc { |f| f.email.present? } }
  # validates :email, array: {format: { with: URI::MailTo::EMAIL_REGEXP }, if: proc { |f| f.email.present? }}

  # validates_each :urls do |record, attr, value|
  #   # value is an array of hashes
  #   # eg [{'name' => 'hi', 'url' => 'bye'}, ...]
  #
  #   problems = ''
  #   if value
  #     value.each{|name_url|
  #       problems << "Name #{name_url['name']} is missing its url. " \
  #         unless name_url['url']}
  #   else
  #     problems = 'Please supply at least one name and url'
  #   end
  #   record.errors.add(:urls, problems) unless problems.empty?
  # end

end
