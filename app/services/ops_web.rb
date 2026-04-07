require 'rest-client'
require 'json'


class OpsWeb
	def self.send_message_to_dna_api(msg)
		payload = {
			object_id: msg.id,
			object_type: msg.class.to_s,
			behavior: 'SEND_SMS'
		}
		http_post(payload)
	end


	def self.http_post payload_hsh

		response = RestClient.post(
		    "#{SITE_URL}/#{SITE_SLUG}/internals/",
		    payload_hsh.to_json,
		    { :content_type => :json, accept: :json, :'Api-Key' => DNA_API_KEY }
		)

		puts response.inspect
		puts response.class

		if response.class == RestClient::Response
			r = JSON.parse(response.body)
			{ code: response.code, body: r, message: response.description }
		else
			r = JSON.parse(response)
			{ code: response.code, body: r }
		end

	rescue => e

		puts "\n\n 39 HTTP POST ERROR #{e.inspect}"
		if e.nil?
			{ code: 0, error: 'UNKNOWN ERROR RECEIVED', body: e }
		elsif e.class == Errno::ECONNREFUSED
			{ code: 0, error: e.message, body: e }
		else
			resp = e.response.code
			puts "\n\nHTTP POST ERROR  code = #{resp}\n #{e.inspect}\n\n"
			{ code: e.response.code, error: e.response['error'], body: e }
		end

	end


end



__END__

m = Message.last
x = OpsWeb.send_message_to_dna_api(m)