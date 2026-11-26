module Spree
  module Api
    module V1
      # POST /api/v1/affiliate/clicks { code, landing_path, referrer }. No auth; credentials are ignored.
      #
      #   200 { ok: true, cookie_days }  click accepted for an approved affiliate
      #   204                            unknown code, or the affiliate isn't approved
      #   429 { error }                  over Affiliates.config.rate_limits[:click] for this visitor
      #
      # Stored: the landing path without its query string, the referrer's host only and a daily
      # visitor hash (AffiliateClick.visitor_hash). Raw IPs are never stored. The same visitor
      # through the same code within Affiliates.config.click_dedupe_window is counted once.
      class AffiliateClicksController < Spree::Api::BaseController
        skip_before_action :load_user, :authorize_for_order, :authenticate_user, :load_user_roles, raise: false

        def create
          visitor_hash = AffiliateClick.visitor_hash(ip: request.remote_ip, user_agent: request.user_agent)
          unless Affiliates::RateLimit.allow?(:click, visitor_hash)
            return render json: { error: 'Too many requests. Try again later.' }, status: :too_many_requests
          end

          account = AffiliateAccount.approved.find_by_code(scalar(params[:code]))
          return head :no_content unless account

          unless recent_click?(account, visitor_hash)
            AffiliateClick.create!(
              affiliate_account: account,
              landing_path: AffiliateClick.landing_path_for(scalar(params[:landing_path])),
              referrer_host: AffiliateClick.referrer_host_for(scalar(params[:referrer])),
              visitor_hash: visitor_hash
            )
          end
          render json: { ok: true, cookie_days: account.cookie_days }
        end

        private

        def recent_click?(account, visitor_hash)
          account.clicks.where(visitor_hash: visitor_hash)
                 .where('created_at > ?', Affiliates.config.click_dedupe_window.ago).exists?
        end

        def scalar(value)
          value.is_a?(String) ? value : nil
        end
      end
    end
  end
end
