class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true
  belongs_to :receiver, polymorphic: true
  belongs_to :thread, class_name: "ThreadTable", optional: :true
  after_create :assign_thread_id
  def assign_thread_id
    if self.sender.sent_messages.where(receiver_id: self.receiver.id)&.last&.created_at > 7.days
      thread_table = ThreadTable.create(stale: true, archived: true)
      self.update(thread_table_id: thread_table.id)
    else
      thread_table_id = self.sender.sent_messages.where(receiver_id: self.receiver.id)&.last&.thread_table_id
      self.update(thread_table_id: thread_table_id)
    end
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
