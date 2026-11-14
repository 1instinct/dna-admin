module Spree
  module Admin
    # The "Affiliates" tab: applications (status filter) and accounts. Approve (with an optional
    # commission override), reject, suspend, reinstate, and edit the terms.
    class AffiliateAccountsController < Spree::Admin::BaseController
      PER_PAGE = 50

      before_action :load_account, except: :index

      def index
        @status = AffiliateAccount::STATUSES.include?(params[:status]) ? params[:status] : nil
        @query = params[:q].to_s.strip
        scope = AffiliateAccount.includes(:user).order(created_at: :desc)
        scope = scope.where(status: @status) if @status
        if @query.present?
          like = "%#{AffiliateAccount.sanitize_sql_like(@query.downcase)}%"
          scope = scope.left_joins(:user).where("affiliate_accounts.code LIKE :q OR lower(#{Spree.user_class.table_name}.email) LIKE :q", q: like)
        end
        @accounts = scope.page(params[:page]).per(PER_PAGE)
        @counts = AffiliateAccount.group(:status).count
      end

      def show
        AffiliateCommission.sweep!
        @totals = @account.totals
        @payable = Affiliates::Payouts.payable(@account)
        @commissions = @account.commissions.includes(:order).order(created_at: :desc).limit(20)
      end

      def update
        attrs = params.require(:affiliate_account).permit(:commission_bps, :cookie_days, :payout_email, :review_note)
        attrs[:commission_bps] = attrs[:commission_bps].presence if attrs.key?(:commission_bps)
        save_with_flash(attrs, 'Affiliate updated')
      end

      def approve
        attrs = review_attrs.merge(status: 'approved', approved_at: Time.current)
        attrs[:commission_bps] = params[:commission_bps].presence if params.key?(:commission_bps)
        save_with_flash(attrs, 'Affiliate approved')
      end

      def reject
        save_with_flash(review_attrs.merge(status: 'rejected', approved_at: nil), 'Application rejected')
      end

      def suspend
        save_with_flash(review_attrs.merge(status: 'suspended'), 'Affiliate suspended')
      end

      def reinstate
        save_with_flash(review_attrs.merge(status: 'approved', approved_at: @account.approved_at || Time.current),
                        'Affiliate reinstated')
      end

      private

      def model_class
        AffiliateAccount
      end

      def load_account
        @account = AffiliateAccount.find(params[:id])
      end

      def review_attrs
        attrs = { reviewed_by_id: try_spree_current_user&.id }
        attrs[:review_note] = params[:review_note].to_s.strip.presence if params.key?(:review_note)
        attrs
      end

      def save_with_flash(attrs, message)
        if @account.update(attrs)
          flash[:success] = message
        else
          flash[:error] = @account.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_affiliate_account_path(@account)
      end
    end
  end
end
