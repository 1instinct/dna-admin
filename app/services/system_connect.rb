class SystemConnect

	# dispatch message
	# contact API to send message on relevant network
	def self.send_sms message_id

		if message_id.kind_of?(Message)
			msg = message_id
		else
			msg = Message.find(message_id)
		end

		OpsWeb.send_message_to_dna_api(msg)


	end








end