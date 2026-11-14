module Spree
  module Api
    module V1
      module Creator
        # A creator's sales.
        #
        #   GET /api/v1/creator/sales?from&to&product_id
        #       200 { series: [{ date, units, gross, earned }],
        #             rows: [{ order_masked, product_id, units, gross, earned, state, created_at }] }
        #       404 when product_id is not the creator's; 422 for a bad range
        #
        # from and to are dates (YYYY-MM-DD) in the app time zone, default the last 30 days, at most
        # 366 days. series has one row per day, zeros included, without void sales; rows are every
        # sale in the range, void ones included, newest first (Creators.config.sales_rows_limit).
        # Order numbers are masked to their last four characters; no buyer data is returned.
        class SalesController < Spree::Api::V1::Creator::BaseController
          MAX_DAYS = 366

          def index
            range = date_range
            return render_error('from and to must be dates, from before to, at most 366 days apart', :unprocessable_entity) unless range

            scope = Spree::CreatorEarning.where(creator_account_id: creator_account.id)
                                         .where(created_at: range.first.beginning_of_day..range.last.end_of_day)
            if params[:product_id].present?
              product = Spree::Product.with_deleted.find_by(id: params[:product_id], creator_id: current_api_user.id)
              return render_not_found unless product

              scope = scope.joins(:line_item).where(spree_line_items: { variant_id: product.variants_including_master.with_deleted.select(:id) })
            end

            Spree::CreatorEarning.sweep!
            earnings = scope.includes(:order, line_item: :variant).order(created_at: :desc, id: :desc).to_a
            render json: { series: series(range, earnings), rows: rows(earnings) }
          end

          private

          def date_range
            to = params[:to].present? ? Date.iso8601(params[:to].to_s) : Time.zone.today
            from = params[:from].present? ? Date.iso8601(params[:from].to_s) : to - 29
            return nil if from > to || (to - from).to_i >= MAX_DAYS

            from..to
          rescue ArgumentError
            nil
          end

          def series(range, earnings)
            by_day = earnings.reject(&:void?).group_by { |earning| earning.created_at.in_time_zone.to_date }
            range.map do |date|
              day = by_day.fetch(date, [])
              { date: date.iso8601, units: day.sum { |e| units(e) }, gross: money(day.sum(&:net_gross)),
                earned: money(day.sum(&:amount)) }
            end
          end

          def rows(earnings)
            earnings.first(Creators.config.sales_rows_limit).map do |earning|
              { order_masked: earning.order_masked, product_id: earning.line_item&.variant&.product_id,
                units: units(earning), gross: money(earning.net_gross), earned: money(earning.amount), state: earning.state,
                created_at: earning.created_at.iso8601 }
            end
          end

          def units(earning)
            earning.line_item&.quantity.to_i
          end

          def money(amount)
            amount.to_d.round(2).to_f
          end
        end
      end
    end
  end
end
