module Spree
  module Api
    module V1
      # POST /api/v1/feedback, JSON or multipart (multipart to send a screenshot).
      #
      # Auth optional: a valid bearer links the feedback to that user; an invalid one is 401.
      # Anonymous requests must send install_id.
      #
      # Fields: kind (bug|idea|other|rating), message (required unless rating, <= 2000), rating
      # (1-5, required for rating), moment, email, install_id, platform, os_version, device_model,
      # app_version, build_number, channel, locale, sentry_event_id, diagnostics (a JSON object,
      # or a string holding one, <= 64 KB as compact JSON), screenshot (file, JPEG or PNG, <= 5 MB).
      #
      # 201 { id }; 422 { error, fields }; 429 { error } past 10 a day per user or install, or 30 a
      # day per IP. A `bug` emails FEEDBACK_EMAIL when set, inline; a mail failure never fails the
      # request.
      class FeedbackController < Spree::Api::BaseController
        include Profiles::ApiResponses

        FIELDS = %i[kind message rating moment email install_id platform os_version device_model app_version
                    build_number channel locale sentry_event_id].freeze

        skip_before_action :authenticate_user
        before_action :reject_bad_credentials

        def create
          feedback = AppFeedback.new(attributes)
          return render_record_errors(feedback, 'Feedback could not be sent') unless diagnostics_ok?(feedback)

          screenshot = params[:screenshot]
          if screenshot.present?
            return unless attach_screenshot(feedback, screenshot)
          end
          return render_record_errors(feedback, 'Feedback could not be sent') unless feedback.valid?
          return render_error('Too much feedback. Try again later.', :too_many_requests) unless within_limits?(feedback)

          if feedback.save
            notify(feedback)
            render json: { id: feedback.id }, status: :created
          else
            render_record_errors(feedback, 'Feedback could not be sent')
          end
        end

        private

        def reject_bad_credentials
          render_error('unauthorized', :unauthorized) if api_credentials_present? && current_api_user.nil?
        end

        def attributes
          attrs = FIELDS.index_with { |field| scalar(params[field]) }.compact
          attrs[:kind] = attrs[:kind].to_s.strip.downcase if attrs[:kind]
          attrs[:email] = attrs[:email].to_s.strip.presence if attrs.key?(:email)
          attrs[:message] = attrs[:message].to_s.strip if attrs[:message]
          attrs[:user] = viewer
          attrs
        end

        # Only plain values; a nested hash or array where a string belongs is ignored.
        def scalar(value)
          value.is_a?(String) || value.is_a?(Numeric) ? value : nil
        end

        # diagnostics arrives as an object (JSON body) or a string holding one (multipart).
        def diagnostics_ok?(feedback)
          raw = params[:diagnostics]
          return true if raw.blank?

          if raw.is_a?(String) && raw.bytesize > AppFeedback::DIAGNOSTICS_MAX_BYTES * 4
            feedback.errors.add(:diagnostics, "must be at most #{AppFeedback::DIAGNOSTICS_MAX_BYTES / 1.kilobyte} KB")
            return false
          end

          value = raw.is_a?(String) ? parse_json(raw) : raw
          value = value.to_unsafe_h if value.is_a?(ActionController::Parameters)
          if value.is_a?(Hash)
            feedback.diagnostics = value
            return true
          end

          feedback.errors.add(:diagnostics, 'must be a JSON object')
          false
        end

        def parse_json(raw)
          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end

        def attach_screenshot(feedback, upload)
          unless upload.respond_to?(:tempfile) || upload.respond_to?(:path)
            render_error('screenshot must be an image file', :unprocessable_entity,
                         fields: { screenshot: ['must be a JPEG or PNG image'] })
            return false
          end
          if upload.size > AppFeedback::SCREENSHOT_MAX_BYTES
            render_error('screenshot is too large', :unprocessable_entity,
                         fields: { screenshot: ["must be at most #{AppFeedback::SCREENSHOT_MAX_BYTES / 1.megabyte} MB"] })
            return false
          end

          path = upload.respond_to?(:tempfile) ? upload.tempfile.path : upload.path
          # Sniffed from the bytes, not the declared type or the file name.
          detected = Marcel::MimeType.for(Pathname.new(path))
          unless AppFeedback::SCREENSHOT_CONTENT_TYPES.include?(detected)
            render_error('screenshot must be a JPEG or PNG image', :unprocessable_entity,
                         fields: { screenshot: ['must be a JPEG or PNG image'] })
            return false
          end

          extension = detected == 'image/png' ? 'png' : 'jpg'
          feedback.screenshot.attach(io: File.open(path, 'rb'), filename: "screenshot.#{extension}", content_type: detected)
          true
        end

        def within_limits?(feedback)
          sender = AppFeedback::RateLimit.sender_key(feedback.user, feedback.install_id)
          AppFeedback::RateLimit.allow?(:sender, sender) &&
            AppFeedback::RateLimit.allow?(:ip, AppFeedback::RateLimit.ip_key(request.remote_ip))
        end

        def notify(feedback)
          return unless feedback.kind == 'bug'
          return Rails.logger.warn('[feedback] FEEDBACK_EMAIL is not set; bug report not emailed') unless AppFeedback.config.notify_email

          AppFeedbackMailer.new_bug(feedback).deliver_now
        rescue StandardError => e
          Rails.logger.error("[feedback] feedback #{feedback.id} email failed: #{e.class}")
        end
      end
    end
  end
end
