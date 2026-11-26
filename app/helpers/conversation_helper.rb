module ConversationHelper
  # A round avatar with the person's initials, drawn locally. (These used to be
  # images from ui-avatars.com, which put every customer's name in a request
  # to a third party.)
  def initials_avatar(name, color:, size: 40)
    initials = name.to_s.split(/[\s@._-]+/).reject(&:blank?).first(2).map { |part| part[0] }.join.upcase.presence || '?'
    content_tag(:span, initials,
                class: 'initials-avatar', title: name, role: 'img', 'aria-label': name.to_s,
                style: "width: #{size}px; height: #{size}px; font-size: #{(size * 0.4).round}px; background: #{color};")
  end

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
        name:  user_1&.full_name.presence || user_1&.email
      }
    end
    if user_hash.fourth == "Spree::User"
      user_2 = Spree::User.find_by_id(user_hash.third)
      users << {
        type: 'User',
        id: user_2&.id,
        name:  user_2&.email
      }
    elsif user_hash.fourth == "Contact"
      user_2 = Contact.find_by_id(user_hash.third)
      users << {
        type: 'Contact',
        id: user_2&.id,
        name:  user_2&.full_name.presence || user_2&.email
      }
    end
    return users
  end

  def fetch_users_from_message(message_id)
    message = Message.find_by_id(message_id)
    users = []
    if message.sender_type == "Spree::User"
      users << {
        type: 'User',
        id: message&.sender&.id,
        name:  message&.sender&.email
      }
    elsif message.sender_type == "Contact"
      users << {
        type: 'Contact',
        id: message&.sender&.id,
        name: message&.sender&.full_name
      }
    end
    if message.receiver_type == "Spree::User"
      users << {
        type: 'User',
        id: message&.receiver&.id,
        name:  message&.receiver&.email
      }
    elsif message.receiver_type == "Contact"
      users << {
        type: 'Contact',
        id: message&.receiver&.id,
        name: message&.receiver&.full_name
      }
    end
    return users
  end
end
