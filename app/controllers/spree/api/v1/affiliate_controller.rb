module Spree
  module Api
    module V1
      # The signed-in user's affiliate account. Bearer required (401 otherwise).
      #
      #   GET   /api/v1/affiliate                 { status, code, link, commission_bps, cookie_days,
      #                                             application, payout_email, totals: { clicks, orders,
      #                                             conversion, pending, approved, paid, currency } }
      #                                           404 before applying
      #   POST  /api/v1/affiliate                 apply: { code?, website, audience, channels[], message,
      #                                           payout_email } -> 201 (same shape); 422 when already
      #                                           applied (a rejected applicant may apply again)
      #   PATCH /api/v1/affiliate                 { code (only while pending), payout_email, website,
      #                                           audience, channels, message } -> 200
      #   GET   /api/v1/affiliate/stats?from&to   { series: [{ date, clicks, orders, commission }] }, one row
      #                                           per day (default the last 30 days, at most 366)
      #   GET   /api/v1/affiliate/commissions?page  { rows: [{ order_masked, base_amount, amount, state,
      #                                           created_at, approvable_at }], page, pages }, 25 a page
      #   GET   /api/v1/affiliate/payouts         { payouts: [{ id, amount, currency, reference, paid_at }] }
      #                                           (the admin's payout note stays internal)
      #   GET   /api/v1/affiliate/code_available?code=  { available }
      #
      # Money is a number in the account's currency. Affiliates never see buyer names or emails;
      # order numbers are masked to their last four characters.
      class AffiliateController < Spree::Api::BaseController
        include Profiles::ApiResponses

        PER_PAGE = 25
        DEFAULT_DAYS = 30
        MAX_DAYS = 366
        APPLICATION_FIELDS = %w[website audience message].freeze

        before_action :require_bearer_user
        before_action :load_account, except: %i[create code_available]
        before_action :sweep, only: %i[show stats commissions]

        def show
          render json: account_json(@account)
        end

        def create
          account = current_api_user.affiliate_account
          if account && !account.rejected?
            return render_error('You have already applied', :unprocessable_entity)
          end

          account ||= AffiliateAccount.new(user: current_api_user)
          account.assign_attributes(status: 'pending', review_note: nil, reviewed_by_id: nil, approved_at: nil)
          account.code = params[:code] if params[:code].is_a?(String) && params[:code].present?
          account.payout_email = params[:payout_email] if params.key?(:payout_email)
          account.application = application_from_params({})
          save_and_render(account, :created)
        end

        def update
          if params[:code].is_a?(String) && AffiliateAccount.normalize_code(params[:code]) != @account.code
            unless @account.pending?
              return render_error('The code can only change while the application is pending', :unprocessable_entity,
                                  fields: { code: ['can only change while pending'] })
            end

            @account.code = params[:code]
          end
          @account.payout_email = params[:payout_email] if params.key?(:payout_email)
          @account.application = application_from_params(@account.application || {})
          save_and_render(@account, :ok)
        end

        def stats
          range = date_range
          return unless range

          from = range.first.beginning_of_day
          to = range.last.end_of_day
          clicks = count_by_day(@account.clicks.where(created_at: from..to))
          commissions = @account.commissions.where(created_at: from..to).where.not(state: 'void')
          orders = count_by_day(commissions)
          amounts = commissions.group(day_sql).sum(:amount).transform_keys(&:to_s)

          series = range.map do |date|
            key = date.iso8601
            { date: key, clicks: clicks[key] || 0, orders: orders[key] || 0, commission: money(amounts[key]) }
          end
          render json: { series: series }
        end

        def commissions
          scope = @account.commissions.includes(:order).order(created_at: :desc, id: :desc)
          total = scope.count
          pages = [(total.to_f / PER_PAGE).ceil, 1].max
          page = params[:page].to_i.clamp(1, pages)
          rows = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map do |commission|
            {
              order_masked: commission.order_masked,
              base_amount: money(commission.base_amount),
              amount: money(commission.amount),
              state: commission.state,
              created_at: commission.created_at&.iso8601,
              approvable_at: commission.approvable_at&.iso8601
            }
          end
          render json: { rows: rows, page: page, pages: pages }
        end

        def payouts
          payouts = @account.payouts.order(paid_at: :desc, id: :desc).map do |payout|
            { id: payout.id, amount: money(payout.amount), currency: payout.currency, reference: payout.reference,
              paid_at: payout.paid_at&.iso8601 }
          end
          render json: { payouts: payouts }
        end

        def code_available
          code = params[:code].is_a?(String) ? params[:code] : ''
          render json: { available: AffiliateAccount.code_available?(code, user: current_api_user) }
        end

        private

        def load_account
          @account = current_api_user.affiliate_account
          render_not_found unless @account
        end

        def sweep
          AffiliateCommission.sweep!
        end

        def save_and_render(account, status)
          if account.save
            render json: account_json(account), status: status
          else
            render_record_errors(account, 'Affiliate account could not be saved')
          end
        rescue ActiveRecord::RecordNotUnique
          account.errors.add(:code, 'has already been taken')
          render_record_errors(account, 'Affiliate account could not be saved')
        end

        # Merges the application fields sent onto `current`.
        def application_from_params(current)
          data = current.to_h.stringify_keys.slice(*AffiliateAccount::APPLICATION_KEYS)
          APPLICATION_FIELDS.each do |field|
            next unless params.key?(field)

            value = params[field]
            data[field] = value.is_a?(String) ? value.strip : nil
          end
          if params.key?(:channels)
            channels = params[:channels]
            data['channels'] = channels.is_a?(Array) ? channels.map { |c| c.is_a?(String) ? c.strip : c }.reject(&:blank?) : channels
          end
          data
        end

        def account_json(account)
          {
            status: account.status,
            code: account.code,
            link: account.link,
            commission_bps: account.effective_commission_bps,
            cookie_days: account.cookie_days,
            application: account.application_data,
            payout_email: account.payout_email,
            totals: account.totals
          }
        end

        def date_range
          to = params[:to].present? ? parse_date(params[:to]) : Date.current
          from = params[:from].present? ? parse_date(params[:from]) : to && to - (DEFAULT_DAYS - 1)
          if from.nil? || to.nil?
            render_error('from and to must be dates (YYYY-MM-DD)', :unprocessable_entity)
            return
          end
          if from > to || (to - from).to_i + 1 > MAX_DAYS
            render_error("from must be on or before to, at most #{MAX_DAYS} days apart", :unprocessable_entity)
            return
          end

          from..to
        end

        def parse_date(value)
          Date.iso8601(value.to_s)
        rescue ArgumentError
          nil
        end

        # The calendar day in the app's time zone, as YYYY-MM-DD.
        def day_sql
          zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.identifier)
          Arel.sql("to_char(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone}, 'YYYY-MM-DD')")
        end

        def count_by_day(scope)
          scope.group(day_sql).count.transform_keys(&:to_s)
        end

        def money(value)
          (value || 0).to_d.round(2).to_f
        end
      end
    end
  end
end
