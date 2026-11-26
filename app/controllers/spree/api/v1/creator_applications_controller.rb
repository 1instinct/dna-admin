module Spree
  module Api
    module V1
      # The signed-in user's application to become a creator. Bearer required (401 otherwise).
      #
      #   GET    /api/v1/creator_application  200 Application (the latest) | 404
      #   POST   /api/v1/creator_application  { display_name, kinds: [String], portfolio_links: [{ label, url }],
      #                                         about, sample_upload_signed_ids: [String] (at most 3) }
      #                                       201 Application | 422 { error, fields } (already pending,
      #                                       already a creator, invalid)
      #   DELETE /api/v1/creator_application  200 Application (withdrawn) | 404 | 422 when none is pending
      #
      # Application: { id, status, display_name, kinds, portfolio_links, about,
      #                samples: [{ id, filename, byte_size, content_type, url }],
      #                review_note, reviewed_at, created_at, updated_at }
      class CreatorApplicationsController < Spree::Api::BaseController
        include Profiles::ApiResponses

        before_action :require_bearer_user

        def show
          application = latest
          return render_not_found unless application

          render json: application_json(application)
        end

        def create
          return render_error('You are already a creator', :unprocessable_entity) if Creators.creator?(current_api_user)
          if Spree::CreatorApplication.pending.exists?(user_id: current_api_user.id)
            return render_error('You already have a pending application', :unprocessable_entity)
          end

          application = Spree::CreatorApplication.new(application_params.merge(user: current_api_user))
          return render_record_errors(application) unless application.save

          render json: application_json(application.reload), status: :created
        rescue ActiveRecord::RecordNotUnique
          render_error('You already have a pending application', :unprocessable_entity)
        end

        def destroy
          application = latest
          return render_not_found unless application
          return render_error('No pending application to withdraw', :unprocessable_entity) unless application.pending?

          application.withdraw!
          render json: application_json(application)
        end

        private

        def latest
          Spree::CreatorApplication.where(user_id: current_api_user.id).newest_first.first
        end

        def application_params
          {
            display_name: params[:display_name],
            kinds: Array(params[:kinds]).map(&:to_s),
            portfolio_links: portfolio_links,
            about: params[:about],
            sample_upload_signed_ids: Array(params[:sample_upload_signed_ids]).map(&:to_s)
          }
        end

        # [{ label, url }] from JSON or form params; anything else is left for validation to refuse.
        def portfolio_links
          raw = params[:portfolio_links]
          raw = raw.values if raw.is_a?(ActionController::Parameters) && raw.keys.all? { |k| k.to_s =~ /\A\d+\z/ }
          Array(raw).map do |link|
            link.respond_to?(:to_unsafe_h) ? link.to_unsafe_h.slice('label', 'url') : link
          end
        end

        def application_json(application)
          ActiveStorage::Current.host ||= request.base_url
          {
            id: application.id,
            status: application.status,
            display_name: application.display_name,
            kinds: application.kinds,
            portfolio_links: application.portfolio_links,
            about: application.about,
            samples: application.samples.attachments.includes(:blob).order(:id).map { |file| sample_json(file) },
            review_note: application.review_note,
            reviewed_at: application.reviewed_at&.iso8601,
            created_at: application.created_at.iso8601,
            updated_at: application.updated_at.iso8601
          }
        end

        def sample_json(file)
          { id: file.id, filename: file.filename.to_s, byte_size: file.byte_size, content_type: file.content_type,
            url: Rails.application.routes.url_helpers.rails_blob_url(file, host: request.base_url) }
        end
      end
    end
  end
end
