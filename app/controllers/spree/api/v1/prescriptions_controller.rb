module Spree
  module Api
    module V1
      class PrescriptionsController < Spree::Api::BaseController
        before_action :authenticate_user

        def index
          user = @current_api_user
          prescriptions = Prescription
            .joins(:patient_mapping)
            .where(patient_mappings: { spree_user_id: user.id })
            .order(received_at: :desc)

          render json: {
            prescriptions: prescriptions.map { |rx| serialize_prescription(rx) }
          }
        end

        def show
          user = @current_api_user
          prescription = Prescription
            .joins(:patient_mapping)
            .where(patient_mappings: { spree_user_id: user.id })
            .find_by(id: params[:id])

          if prescription
            render json: { prescription: serialize_prescription(prescription) }
          else
            render json: { error: "not_found" }, status: :not_found
          end
        end

        private

        def serialize_prescription(rx)
          {
            id: rx.id,
            drug_name: rx.drug_name,
            status: rx.status,
            received_at: rx.received_at,
            expire_date: rx.expire_date,
            refills_left: rx.refills_left,
            prescriber_name: rx.prescriber_name,
            ndc: rx.ndc,
            written_qty: rx.written_qty,
            created_at: rx.created_at,
            updated_at: rx.updated_at
          }
        end
      end
    end
  end
end
