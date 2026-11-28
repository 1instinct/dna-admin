module Spree
  module Api
    module V1
      module Storefront
        # POST /api/v1/storefront/visits
        #   { url, title?, referrer?, utm?: { source, medium, campaign }, order_token? }
        #
        # A page view and heartbeat: the widget sends it on every route change and every 60 s
        # while the tab is visible. order_token is the guest cart's; a signed-in customer's current
        # cart is found from their account. Makes the contact and session when needed and returns
        # 200 { visitor_token, session_id }. 422 without a url.
        class VisitsController < Spree::Api::V1::Storefront::BaseController
          def create
            url = string_param(:url)
            return render_error('url is required', :unprocessable_entity, fields: { url: ["can't be blank"] }) if url.blank?

            contact = current_contact(create: true)
            session = Visitors::Tracker.new(contact, Visitors::Tracker.request_info(request)).ping(
              url: url, title: string_param(:title), referrer: string_param(:referrer),
              utm: params[:utm], order_token: string_param(:order_token), user: viewer
            )
            render json: { visitor_token: contact.visitor_token, session_id: session.token }
          end
        end
      end
    end
  end
end
