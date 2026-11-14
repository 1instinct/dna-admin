module Spree
  module Api
    module V1
      module Creator
        # A creator's payouts, newest first.
        #
        #   GET /api/v1/creator/payouts  200 { payouts: [{ id, amount, currency, reference, paid_at, note }] }
        class PayoutsController < Spree::Api::V1::Creator::BaseController
          def index
            payouts = Spree::CreatorPayout.where(creator_account_id: creator_account.id).order(paid_at: :desc, id: :desc)
            render json: {
              payouts: payouts.map do |payout|
                { id: payout.id, amount: payout.amount.to_d.round(2).to_f, currency: payout.currency,
                  reference: payout.reference, paid_at: payout.paid_at.iso8601, note: payout.note }
              end
            }
          end
        end
      end
    end
  end
end
