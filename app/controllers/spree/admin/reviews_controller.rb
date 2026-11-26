module Spree
  module Admin
    # Reviews > Reviews: the moderation queue (waiting first by default) and each review's page.
    #
    # Every decision goes through Reviews::Moderation, which keeps stats and points in step and
    # never looks at the rating. Rejections need a reason from Spree::Review::REJECTION_REASONS,
    # the same list for every star level. Publishing a review that customers reported closes its
    # open reports.
    class ReviewsController < Spree::Admin::BaseController
      PER_PAGE = 50
      STATUS_FILTERS = (%w[all] + Spree::Review::STATUSES).freeze
      BULK_ACTIONS = %w[publish reject hide].freeze
      BULK_DONE = { 'publish' => 'Published', 'reject' => 'Rejected', 'hide' => 'Hid' }.freeze

      before_action :load_review, except: %i[index bulk]

      def index
        @filters = filter_params
        @reviews = filtered(Spree::Review.includes(:reviewable, :user, photos_attachments: :blob))
                   .order(created_at: :desc, id: :desc).page(params[:page]).per(PER_PAGE)
        @counts = Spree::Review.group(:status).count
      end

      def show; end

      def publish
        decide('Review published') do
          Reviews::Moderation.publish!(@review, by: admin)
          close_open_reports(@review, 'Review published')
        end
      end

      def reject
        reason = params[:reason].to_s
        unless Spree::Review::REJECTION_REASONS.include?(reason)
          flash[:error] = 'Choose a reason for rejecting this review.'
          return redirect_to(spree.admin_review_path(@review))
        end

        decide('Review rejected') { Reviews::Moderation.reject!(@review, reason: reason, by: admin) }
      end

      def hide
        decide('Review hidden') { Reviews::Moderation.hide!(@review, by: admin) }
      end

      # A public reply from the store; an empty reply removes it.
      def reply
        body = params[:reply_body].to_s.strip
        attrs = body.present? ? { reply_body: body, reply_author: admin, replied_at: Time.current } : { reply_body: nil, reply_author: nil, replied_at: nil }
        if @review.update(attrs)
          flash[:success] = body.present? ? 'Reply saved' : 'Reply removed'
        else
          flash[:error] = @review.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_review_path(@review)
      end

      def change_channel
        channel = params[:channel].to_s
        unless Spree::Review::CHANNELS.include?(channel)
          flash[:error] = 'Unknown channel'
          return redirect_to(spree.admin_review_path(@review))
        end

        decide("Moved to #{channel}") { Reviews::Moderation.change_channel!(@review, channel: channel, by: admin) }
      end

      def destroy_photo
        attachment = @review.photos.find_by(id: params[:photo_id])
        if attachment
          blob = attachment.blob
          attachment.delete
          Reviews::RefreshStats.call(@review.reviewable) if @review.published?
          begin
            blob.purge
          rescue StandardError => e
            Rails.logger.error("[reviews] admin photo purge blob_key=#{blob.key} failed: #{e.class}")
          end
          flash[:success] = 'Photo removed'
        else
          flash[:error] = 'That photo is already gone'
        end
        redirect_to spree.admin_review_path(@review)
      end

      def bulk
        action = params[:bulk_action].to_s
        ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
        reason = params[:reason].to_s
        if !BULK_ACTIONS.include?(action) || ids.empty?
          flash[:error] = 'Select reviews and an action'
          return redirect_back(fallback_location: spree.admin_reviews_path)
        end
        if action == 'reject' && !Spree::Review::REJECTION_REASONS.include?(reason)
          flash[:error] = 'Choose a reason for rejecting'
          return redirect_back(fallback_location: spree.admin_reviews_path)
        end

        count = 0
        Spree::Review.where(id: ids).find_each do |review|
          case action
          when 'publish'
            Reviews::Moderation.publish!(review, by: admin)
            close_open_reports(review, 'Review published (bulk)')
          when 'reject' then Reviews::Moderation.reject!(review, reason: reason, by: admin)
          when 'hide' then Reviews::Moderation.hide!(review, by: admin)
          end
          count += 1
        end
        flash[:success] = "#{BULK_DONE.fetch(action)} #{count} #{'review'.pluralize(count)}"
        redirect_back fallback_location: spree.admin_reviews_path
      end

      private

      def model_class
        Spree::Review
      end

      def admin
        try_spree_current_user
      end

      def load_review
        @review = Spree::Review.find(params[:id])
      end

      def decide(message)
        yield
        flash[:success] = message
        redirect_to spree.admin_review_path(@review)
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.record.errors.full_messages.to_sentence
        redirect_to spree.admin_review_path(@review)
      end

      def close_open_reports(review, note)
        reports = Spree::ContentReport.about_review(review).where(status: 'open')
        return unless reports.exists?

        reports.find_each { |report| report.resolve!(status: 'dismissed', by: admin, note: note) }
        Reviews::Reports.refresh_count(review)
      end

      def filter_params
        f = params.permit(:status, :rating, :channel, :photos, :reported, :q, :subject, :from, :to).to_h.symbolize_keys
        f[:status] = 'pending' unless STATUS_FILTERS.include?(f[:status])
        f
      end

      def filtered(scope)
        f = @filters
        scope = scope.where(status: f[:status]) unless f[:status] == 'all'
        scope = scope.where(rating: f[:rating].to_i) if (1..5).cover?(f[:rating].to_i)
        scope = scope.where(channel: f[:channel]) if Spree::Review::CHANNELS.include?(f[:channel])
        photo_ids = ActiveStorage::Attachment.where(record_type: Spree::Review.name, name: 'photos').select(:record_id)
        scope = scope.where(id: photo_ids) if f[:photos] == 'yes'
        scope = scope.where.not(id: photo_ids) if f[:photos] == 'no'
        scope = scope.where('reports_count > 0') if f[:reported] == 'yes'
        scope = scope.for_products if f[:subject] == 'product'
        scope = scope.for_store if f[:subject] == 'store'
        if f[:q].present?
          like = "%#{Spree::Review.sanitize_sql_like(f[:q].strip)}%"
          product_ids = Spree::Product.with_deleted.where('spree_products.name ILIKE ?', like).select(:id)
          scope = scope.where(reviewable_type: Spree::Product.name, reviewable_id: product_ids).
                  or(scope.where('spree_reviews.title ILIKE :q OR spree_reviews.body ILIKE :q OR spree_reviews.display_name ILIKE :q', q: like))
        end
        from = parse_date(f[:from])
        to = parse_date(f[:to])
        scope = scope.where('spree_reviews.created_at >= ?', from.beginning_of_day) if from
        scope = scope.where('spree_reviews.created_at <= ?', to.end_of_day) if to
        scope
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
