module Spree
  module Api
    module V1
      # POST /api/v1/affiliate/clicks { code, landing_path, referrer }. No auth; credentials are ignored.
      #
      #   200 { ok: true, cookie_days }  click recorded for an approved affiliate
      #   204                            unknown code, or the affiliate isn't approved
      #
      # Stored: the landing path without its query string, the referrer's host only and a daily
      # visitor hash (AffiliateClick.visitor_hash). Raw IPs are never stored.
      class AffiliateClicksController < Spree::Api::BaseController
        skip_before_action :load_user, :authorize_for_order, :authenticate_user, :load_user_roles, raise: false

        def create
          account = AffiliateAccount.approved.find_by_code(scalar(params[:code]))
          return head :no_content unless account

          AffiliateClick.create!(
            affiliate_account: account,
            landing_path: AffiliateClick.landing_path_for(scalar(params[:landing_path])),
            referrer_host: AffiliateClick.referrer_host_for(scalar(params[:referrer])),
            visitor_hash: AffiliateClick.visitor_hash(ip: request.remote_ip, user_agent: request.user_agent)
          )
          render json: { ok: true, cookie_days: account.cookie_days }
        end

        private

        def scalar(value)
          value.is_a?(String) ? value : nil
        end
      end
    end
  end
end
