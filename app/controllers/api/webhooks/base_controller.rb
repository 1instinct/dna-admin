module Api
  module Webhooks
    class BaseController < ActionController::API
      include WebhookAuthentication

      private

      def parsed_payload
        @parsed_payload ||= JSON.parse(request.body.read).tap { request.body.rewind }
      rescue JSON::ParserError
        head :bad_request and return
      end
    end
  end
end
