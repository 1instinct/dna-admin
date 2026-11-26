module Spree
  module Admin
    # Content reports from users. Index shows open reports by default (?status=actioned|dismissed|all).
    # Each action resolves the report with the current admin, the time and an optional note.
    class ContentReportsController < Spree::Admin::BaseController
      before_action :load_report, except: :index

      def index
        @status = params[:status].presence || 'open'
        scope = Spree::ContentReport.includes(:reportable, reporter: :profile).order(created_at: :desc)
        scope = scope.where(status: @status) unless @status == 'all'
        if params[:profile_id].present?
          scope = scope.where(reportable_type: Spree::UserProfile.name, reportable_id: params[:profile_id])
        end
        @reports = scope.page(params[:page]).per(50)
      end

      def show; end

      def dismiss
        resolve('dismissed', 'Report dismissed')
      end

      # Review reports: hide the review, or put it back on the site and close every open report
      # about it (reports had sent it to moderation).
      def hide_review
        act_on_review('Review hidden') { |review| Reviews::Moderation.hide!(review, by: try_spree_current_user) }
      end

      def restore_review
        act_on_review('Review restored') do |review|
          Reviews::Moderation.publish!(review, by: try_spree_current_user)
          Spree::ContentReport.about_review(review).where(status: 'open').where.not(id: @report.id).
            find_each { |other| other.resolve!(status: 'dismissed', by: try_spree_current_user, note: "Review restored from report ##{@report.id}") }
        end
      end

      def hide_profile
        act('Profile hidden') { |profile| Profiles::Moderation.hide(profile, reason: "Report ##{@report.id}: #{note}") }
      end

      def remove_photo
        act('Photo removed') { |profile| Profiles::Moderation.remove_photo(profile) }
      end

      def clear_bio
        act('Bio cleared') { |profile| Profiles::Moderation.clear_bio(profile) }
      end

      def lock_account
        act('Account locked') { |profile| Profiles::Moderation.lock(profile.user) }
      end

      private

      def model_class
        Spree::ContentReport
      end

      def load_report
        @report = Spree::ContentReport.find(params[:id])
        @profile = @report.reportable if @report.reportable.is_a?(Spree::UserProfile)
        @review = @report.reportable if @report.reportable.is_a?(Spree::Review)
      end

      def act_on_review(message)
        unless @review
          flash[:error] = 'The reported review no longer exists.'
          return redirect_to(spree.admin_content_report_path(@report))
        end

        yield @review
        resolve('actioned', message)
      end

      def note
        params[:resolution_note].to_s.strip
      end

      def act(message)
        unless @profile
          flash[:error] = 'The reported profile no longer exists.'
          return redirect_to(spree.admin_content_report_path(@report))
        end

        yield @profile
        resolve('actioned', message)
      rescue Profiles::Moderation::Refused => e
        flash[:error] = e.message
        redirect_to spree.admin_content_report_path(@report)
      end

      def resolve(status, message)
        resolution = status == 'actioned' ? [message, note.presence].compact.join(': ') : note.presence
        @report.resolve!(status: status, by: try_spree_current_user, note: resolution)
        Reviews::Reports.refresh_count(@review) if @review
        flash[:success] = message
        redirect_to spree.admin_content_reports_path
      end
    end
  end
end
