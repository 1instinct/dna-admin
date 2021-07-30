module ConversationHelper
  def fetch_users(user_hash)
    users = []
    if user_hash.second == "Spree::User"
      user_1 = Spree::User.find_by_id(user_hash.first)
      users << {
        type: 'User',
        id: user_1&.id,
        name:  user_1&.email
      }
    elsif user_hash.second == "Contact"
      user_1 = Contact.find_by_id(user_hash.first)
      users << {
        type: 'Contact',
        id: user_1&.id,
        name:  user_1&.full_name
      }
    end
    if user_hash.fourth == "Spree::User"
      user_2 = Spree::User.find_by_id(user_hash.third)
      users << {
        type: 'Contact',
        id: user_2&.id,
        name:  user_2&.email
      }
    elsif user_hash.fourth == "Contact"
      user_2 = Contact.find_by_id(user_hash.third)
      users << {
        type: 'Contact',
        id: user_2&.id,
        name:  user_2&.email
      }
    end
    return users
  end  
end
