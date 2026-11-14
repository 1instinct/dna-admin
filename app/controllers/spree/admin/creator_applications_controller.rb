module Spree
  module Admin
    # Creators tab: applications to become a creator. Filter by status (default pending); the
    # detail page plays the demo files; approve or reject with a note (Creators::Approver).
    class CreatorApplicationsController < Spree::Admin::BaseController
      PER_PAGE = 50

      before_action :load_application, only: %i[show approve reject]

      def index
        @status = Spree::CreatorApplication::STATUSES.include?(params[:status]) ? params[:status] : (params.key?(:status) ? nil : 'pending')
        scope = Spree::CreatorApplication.includes(:user).newest_first
        scope = scope.where(status: @status) if @status
        @counts = Spree::CreatorApplication.group(:status).count
        @applications = scope.page(params[:page]).per(PER_PAGE)
      end

      def show
        @account = Spree::CreatorAccount.find_by(user_id: @application.user_id)
        @samples = @application.samples.attachments.includes(:blob).order(:id)
      end

      def approve
        decide(:approve!, "#{@application.display_name} is now a creator")
      end

      def reject
        decide(:reject!, 'Application rejected')
      end

      private

      def decide(action, message)
        begin
          Creators::Approver.public_send(action, @application, try_spree_current_user, params[:review_note])
          flash[:success] = message
        rescue Spree::CreatorApplication::NotPending => e
          flash[:error] = e.message
        end
        redirect_to spree.admin_creator_application_path(@application)
      end

      def model_class
        Spree::CreatorApplication
      end

      def load_application
        @application = Spree::CreatorApplication.find(params[:id])
      end
    end
  end
end
