module Spree
  module Api
    module V1
      class StoreController < ::Spree::Api::V1::BaseController
        def show
          store = Spree::Store.default || Spree::Store.first
          render json: {
            data: {
              id: store.id.to_s,
              type: "store",
              attributes: {
                name: store.name,
                url: store.url,
                meta_description: store.meta_description,
                meta_keywords: store.meta_keywords,
                seo_title: store.seo_title,
                default_currency: store.default_currency,
                default: store.default,
                supported_currencies: store.supported_currencies,
                facebook: store.facebook,
                twitter: store.twitter,
                instagram: store.instagram,
                default_locale: store.default_locale,
                customer_support_email: store.customer_support_email,
                description: store.description,
                address: store.address,
                contact_phone: store.contact_phone,
                supported_locales: store.supported_locales,
                favicon_path: ActionController::Base.helpers.asset_path("favicon.ico")
              },
              relationships: {
                default_country: {
                  data: {
                    id: store.default_country_id.to_s,
                    type: "country"
                  }
                }
              }
            }
          }
        end
      end
    end
  end
end
