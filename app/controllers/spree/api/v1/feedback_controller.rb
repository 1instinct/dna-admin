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

          screenshot = nil
          if params[:screenshot].present?
            screenshot = checked_screenshot(params[:screenshot])
            return unless screenshot
          end
          return render_record_errors(feedback, 'Feedback could not be sent') unless feedback.valid?
          return render_error('Too much feedback. Try again later.', :too_many_requests) unless within_limits?(feedback)

          upload_error = screenshot && upload_screenshot(feedback, screenshot)
          if feedback.save
            log_upload_failure(feedback, upload_error) if upload_error
            notify(feedback)
            render json: { id: feedback.id }, status: :created
          else
            discard_uploaded_screenshot(feedback)
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

        # { path:, content_type: } for an upload that is a JPEG or PNG of at most 5 MB, or nil after
        # rendering the 422.
        def checked_screenshot(upload)
          unless upload.respond_to?(:tempfile) || upload.respond_to?(:path)
            render_error('screenshot must be an image file', :unprocessable_entity,
                         fields: { screenshot: ['must be a JPEG or PNG image'] })
            return
          end
          if upload.size > AppFeedback::SCREENSHOT_MAX_BYTES
            render_error('screenshot is too large', :unprocessable_entity,
                         fields: { screenshot: ["must be at most #{AppFeedback::SCREENSHOT_MAX_BYTES / 1.megabyte} MB"] })
            return
          end

          path = upload.respond_to?(:tempfile) ? upload.tempfile.path : upload.path
          # Sniffed from the bytes, not the declared type or the file name.
          detected = Marcel::MimeType.for(Pathname.new(path))
          unless AppFeedback::SCREENSHOT_CONTENT_TYPES.include?(detected)
            render_error('screenshot must be a JPEG or PNG image', :unprocessable_entity,
                         fields: { screenshot: ['must be a JPEG or PNG image'] })
            return
          end

          { path: path, content_type: detected }
        end

        # Uploads to storage before the row is saved, then attaches the stored blob. Rails 6.1
        # would otherwise upload after commit, where a storage error turns into a 500 for a row
        # already saved (and a retry from the app into a duplicate). On failure the feedback is
        # kept without its screenshot, noted for the admin; returns the error, or nil.
        def upload_screenshot(feedback, screenshot)
          extension = screenshot[:content_type] == 'image/png' ? 'png' : 'jpg'
          # A key chosen here, so a blob row left by a failed upload can be found and removed.
          key = ActiveStorage::Blob.generate_unique_secure_token
          File.open(screenshot[:path], 'rb') do |io|
            blob = ActiveStorage::Blob.create_and_upload!(key: key, io: io, filename: "screenshot.#{extension}",
                                                          content_type: screenshot[:content_type], identify: false)
            feedback.screenshot.attach(blob)
          end
          nil
        rescue StandardError => e
          ActiveStorage::Blob.where(key: key).delete_all if key
          feedback.admin_note = [feedback.admin_note.presence, 'screenshot upload failed'].compact.join("\n")
          e
        end

        def log_upload_failure(feedback, error)
          Rails.logger.error("[feedback] feedback #{feedback.id} screenshot upload failed: #{error.class}")
        end

        # The row didn't save (rare: it validated a moment ago); drop the screenshot stored for it.
        def discard_uploaded_screenshot(feedback)
          feedback.screenshot.blob.purge if feedback.screenshot.attached?
        rescue StandardError => e
          Rails.logger.error("[feedback] discarding an unsaved screenshot failed: #{e.class}")
        end

        def within_limits?(feedback)
          AppFeedback::RateLimit.allow_all?(
            sender: AppFeedback::RateLimit.sender_key(feedback.user, feedback.install_id),
            ip: AppFeedback::RateLimit.ip_key(request.remote_ip)
          )
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
