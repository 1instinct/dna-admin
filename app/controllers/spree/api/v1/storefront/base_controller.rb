module Spree
  module Api
    module V1
      module Storefront
        # The storefront widget's public API (/api/v1/storefront): visit pings and customer chat.
        #
        # Identity is the X-Visitor-Token header, a random id the widget keeps in localStorage
        # (20 to 64 characters of A-Z, a-z, 0-9, _ and -). An unknown well-formed token is accepted: the
        # contact is made for it on the first visit ping or message; responses carry the visitor_token to
        # keep. A signed-in customer's Spree token (Authorization: Bearer, or X-Spree-Token) links
        # the contact to the account; a missing, invalid or expired one is simply anonymous.
        #
        # Errors are { "error": "message", "fields": { ... } } like the app's other v1 endpoints;
        # 429 with Retry-After past a rate limit (Chat.config.rate_limits), per visitor token and per
        # IP. CORS is the app's (config/initializers/cors.rb), which exposes Retry-After.
        class BaseController < Spree::Api::BaseController
          skip_before_action :authenticate_user
          # order_token in a visit ping is the cart's, not a Spree order API credential.
          skip_before_action :authorize_for_order, raise: false

          before_action :reject_malformed_visitor_token
          before_action :limit_requests

          rescue_from Chat::Conversations::Invalid do |e|
            render_error(e.message, :unprocessable_entity)
          end
          rescue_from ActionController::ParameterMissing do |e|
            render_error("#{e.param} is required", :unprocessable_entity)
          end

          private

          def visitor_token_header
            request.headers['X-Visitor-Token'].presence
          end

          def reject_malformed_visitor_token
            return if visitor_token_header.nil? || Contact.valid_visitor_token?(visitor_token_header)

            render_error('invalid visitor token', :unauthorized)
          end

          def limit_requests
            return too_many_requests(:request) unless Chat::RateLimit.allow?(:request, visitor_token_header)

            too_many_requests(:ip_request) unless Chat::RateLimit.allow?(:ip_request, request.remote_ip)
          end

          # A signed-in customer, or nil.
          def viewer
            current_api_user&.persisted? ? current_api_user : nil
          end

          def current_contact(create: false)
            return @current_contact if defined?(@current_contact) && (@current_contact || !create)

            @current_contact = Visitors::Identity.resolve(token: visitor_token_header, user: viewer, create: create)
            touch_last_seen(@current_contact)
            @current_contact
          end

          # 429 with Retry-After: the seconds until the rule's window ends.
          # At most one write a minute per contact: GET chat is polled every 5 s while the widget is open.
          def touch_last_seen(contact)
            return unless contact
            return if contact.last_seen_at && contact.last_seen_at > 1.minute.ago

            contact.update_column(:last_seen_at, Time.current)
          end

          def too_many_requests(rule_name)
            response.headers['Retry-After'] = Chat::RateLimit.retry_after(rule_name).to_s
            render_error('Too many requests. Try again later.', :too_many_requests)
          end

          def render_error(message, status, fields: nil)
            body = { error: message }
            body[:fields] = fields if fields
            render json: body, status: status
          end

          # A plain string param, or nil (a nested object where a string belongs is ignored).
          def string_param(name)
            value = params[name]
            value.is_a?(String) || value.is_a?(Numeric) ? value.to_s : nil
          end
        end
      end
    end
  end
end
