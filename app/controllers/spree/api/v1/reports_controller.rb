module Spree
  module Api
    module V1
      # POST /api/v1/reports { target: { type: "profile", handle }, reason, details }. Bearer required.
      #
      # 201 { id }; 404 unknown, hidden or blocked-either-way target; 422 { error, fields } for an
      # unknown type or reason, details > 500 or reporting yourself; 429 after 20 reports in 24 h.
      # Emails the moderation inbox (MODERATION_EMAIL) when one is configured, inline so a dyno
      # restart can't lose it. A mail failure never fails the report; it stays in the admin.
      class ReportsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        TARGET_TYPES = %w[profile].freeze

        before_action :require_bearer_user

        def create
          target = params.require(:target)
          type = target.is_a?(ActionController::Parameters) ? target[:type].to_s : ''
          unless TARGET_TYPES.include?(type)
            return render_error('Unknown report target', :unprocessable_entity, fields: { target: ['type is not supported'] })
          end

          profile = visible_profile(target[:handle], viewer: current_api_user)
          return render_not_found unless profile
          if profile.user_id == current_api_user.id
            return render_error("You can't report yourself", :unprocessable_entity, fields: { target: ["can't be yourself"] })
          end

          report = Spree::ContentReport.for_profile(profile, reporter: current_api_user, reason: params[:reason],
                                                             details: params[:details])
          if report.save
            notify(report)
            render json: { id: report.id }, status: :created
          elsif report.rate_limited?
            render_error(report.errors[:base].first, :too_many_requests)
          else
            render_record_errors(report, 'Report could not be sent')
          end
        end

        private

        def notify(report)
          return Rails.logger.warn('[profiles] MODERATION_EMAIL is not set; report not emailed') unless Profiles.config.moderation_email

          ModerationMailer.new_report(report).deliver_now
        rescue StandardError => e
          Rails.logger.error("[profiles] report #{report.id} email failed: #{e.class}")
        end
      end
    end
  end
end
