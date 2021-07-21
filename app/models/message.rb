class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true
  belongs_to :receiver, polymorphic: true
  belongs_to :thread, class_name: "ThreadTable", optional: :true

  after_create :assign_thread_id

  def assign_thread_id
    messages = message_transaction_between_two_parties(self.sender, self.receiver)
    message = messages.first
    if messages.count > 0
      if ((Time.now - message.created_at) / 86400).to_i > 7
        thread_table = ThreadTable.create(stale: true, archived: true)
        self.update(thread_table_id: thread_table.id)
      else
        self.update(thread_table_id: message.thread_table_id)
      end
    else
      thread_table = ThreadTable.create(stale: true, archived: true)
      self.update(thread_table_id: thread_table.id)
    end
  end

  def message_transaction_between_two_parties(user_1, user_2)
    user_1_sent_messages = user_1.sent_messages.where(receiver_id: user_2.id).where.not(thread_table_id: nil)
    user_2_sent_messages = user_2.sent_messages.where(receiver_id: user_1.id).where.not(thread_table_id: nil)
    all_messages = (user_1_sent_messages + user_2_sent_messages).sort.reverse{|a,b| a.created_at <=> b.created_at }
  end
end

# class Message < ApplicationRecord

	# def self.admin_conversations
	# 	where.not(sender_type: :admin).order(updated_at: :desc).limit(20)
	# end

	# def self.find_with_sender_id(sender_id, sender_type: nil)
	# 	where(sender_id: sender_id).or(Message.where(receiver_id: sender_id)).order(created_at: :desc).limit(20).reverse
	# end



	# def self.create_message_for_admin body, thread_id, spree_user_id
	# 	raise if thread_id.nil?
	# 	m = new
	# 	m.body = body
	# 	m.sender_id = spree_user_id
	# 	m.sender_type = :admin
	# 	sender_message = Message.where(sender_id: thread_id).last
	# 	raise if sender_message.nil?
	# 	m.receiver_id = sender_message.sender_id
	# 	m.receiver_type = sender_message.sender_type
	# 	m.save
	# 	return m
	# end


#-------------------------------------------------------------------------


	# def username
	# 	self.sender_type + ' ' + self.sender_id
	# end
	# end


# __END__
#
#
#   create_table "messages", force: :cascade do |t|
#     t.boolean "active", default: true
#     t.string "status", default: "unread"
#     t.text "body"
#     t.string "sender_id"
#     t.string "sender_type"
#     t.string "receiver_id"
#     t.string "receiver_type"
#     t.string "channel_id"
#     t.string "message_id"
#     t.string "conversation_id"
#     t.datetime "created_at", null: false
#     t.datetime "updated_at", null: false
#   end
#
#
#   	def self.init_with_twilio twilio_params
# 		tp = twilio_params
# 		m = new
# 		m.status = 'delivered'
# 		m.body = tp["Body"]
# 		m.sender_id = tp["From"].gsub('+','')
# 		m.sender_type = 'sms'
# 		m.receiver_id = tp["To"].gsub('+','')
# 		m.receiver_type = 'twilio'
# 		m.channel_id = tp["AccountSid"]
# 		m.message_id = tp["MessageSid"]
# 		m.conversation_id = tp["SmsSid"]
# 		return m
# 	end
#
# 	def self.create_with_twilio twilio_params
# 		m = init_with_twilio(twilio_params)
# 		m.save
# 		return m
# 	end
