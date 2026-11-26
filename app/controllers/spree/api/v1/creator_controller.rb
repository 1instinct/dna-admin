module Spree
  module Api
    module V1
      # The creator portal overview. Bearer, creator role and an active account required.
      #
      #   GET /api/v1/creator
      #       200 { account: { revenue_share_bps, payout_email, status },
      #             profile: { handle, name, avatar_url },
      #             totals: { gross, earned, payable, paid, currency },
      #             counts: { products_live, products_in_review, sales } }
      #
      # Totals are in the store currency, over all non-void earnings (earned is the creator's
      # share; payable and paid are parts of it). sales counts units sold. Pending earnings past
      # their hold become payable on read.
      class CreatorController < Spree::Api::V1::Creator::BaseController
        def show
          Spree::CreatorEarning.sweep!
          render json: {
            account: { revenue_share_bps: creator_account.revenue_share_bps, payout_email: creator_account.payout_email,
                       status: creator_account.status },
            profile: profile_json,
            totals: totals,
            counts: counts
          }
        end

        private

        def profile_json
          profile = current_api_user.profile
          return { handle: nil, name: nil, avatar_url: nil } unless profile

          avatar = Profiles::Presenter.new(profile, viewer: current_api_user, base_url: request.base_url).own_avatar
          { handle: profile.handle, name: profile.name, avatar_url: avatar && (avatar[:large] || avatar.values.first) }
        end

        def totals
          currency = Spree::Store.default.default_currency.presence || Spree::Config[:currency]
          earnings = Spree::CreatorEarning.counted.where(creator_account_id: creator_account.id, currency: currency)
          sums = earnings.group(:state).sum(:amount)
          {
            gross: money(earnings.sum(Arel.sql('gross - refunded_gross'))),
            earned: money(sums.values.sum),
            payable: money(sums['payable']),
            paid: money(sums['paid']),
            currency: currency
          }
        end

        def counts
          products = Spree::Product.where(creator_id: current_api_user.id)
          live = products.publicly_visible.joins(:master).where(
            Spree::DigitalAsset.published.where('spree_digital_assets.variant_id = spree_variants.id').arel.exists
          )
          sales = Spree::CreatorEarning.counted.where(creator_account_id: creator_account.id).joins(:line_item)
                                       .sum('spree_line_items.quantity')
          { products_live: live.count, products_in_review: products.where(review_state: 'submitted').count,
            sales: sales.to_i }
        end

        def money(amount)
          amount.to_d.round(2).to_f
        end
      end
    end
  end
end
