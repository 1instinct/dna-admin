module Spree
  module Api
    module V1
      # A direct-upload slot for one file. Bearer required (401 otherwise).
      #
      #   POST /api/v1/uploads { filename, byte_size, checksum (base64 MD5), content_type }
      #        201 { signed_id, direct_upload: { url, headers } }
      #        422 { error, fields } when the type, extension or size is not allowed (Uploads.config)
      #        429 past Uploads.config.rate_limit per user
      #
      # The client PUTs the bytes to direct_upload.url with direct_upload.headers, then passes
      # signed_id to the endpoint that attaches the file.
      class UploadsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user

        def create
          unless DigitalAssets::RateLimit.allow?(current_api_user, :uploads, Uploads.config.rate_limit)
            return render_error('Too many requests. Try again later.', :too_many_requests)
          end

          attrs = upload_attributes
          fields = check(attrs)
          return render_error(fields.values.flatten.first, :unprocessable_entity, fields: fields) if fields.any?

          ActiveStorage::Current.host ||= request.base_url
          blob = ActiveStorage::Blob.create_before_direct_upload!(**attrs)
          render json: {
            signed_id: blob.signed_id,
            direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload }
          }, status: :created
        end

        private

        def upload_attributes
          {
            filename: params[:filename].to_s.strip,
            byte_size: Integer(params[:byte_size].to_s, exception: false),
            checksum: params[:checksum].to_s.strip,
            content_type: params[:content_type].to_s.strip.downcase
          }
        end

        def check(attrs)
          fields = {}
          fields[:filename] = ['filename is required'] if attrs[:filename].empty? || attrs[:filename].length > 255
          rule = Uploads.config.rule_for(attrs[:filename], attrs[:content_type])
          fields[:content_type] = ['This file type is not allowed'] unless rule
          size = attrs[:byte_size]
          if size.nil? || size <= 0
            fields[:byte_size] = ['byte_size must be a positive integer']
          elsif rule && size > rule[:max_bytes]
            fields[:byte_size] = ["File is too large (at most #{rule[:max_bytes] / 1.kilobyte} KB)"]
          end
          fields[:checksum] = ['checksum must be a base64 MD5'] unless md5?(attrs[:checksum])
          fields
        end

        def md5?(value)
          Base64.strict_decode64(value).bytesize == 16
        rescue ArgumentError
          false
        end
      end
    end
  end
end
