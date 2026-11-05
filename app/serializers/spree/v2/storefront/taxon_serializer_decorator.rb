# A taxon's `products` relationship, and so include=products and everything below it, lists only
# available products unless an admin is asking. It filters in Ruby because the controllers
# preload `products`. Re-declaring a jsonapi-serializer relationship replaces it by name, so
# loading this more than once is harmless.
module Spree
  module V2
    module Storefront
      module TaxonSerializerDecorator
        def self.apply(serializer)
          serializer.has_many :products, record_type: :product do |taxon, params|
            user = params[:user]
            user&.has_spree_role?('admin') ? taxon.products : taxon.products.select(&:available?)
          end
        end
      end
    end
  end
end

Spree::V2::Storefront::TaxonSerializerDecorator.apply(Spree::V2::Storefront::TaxonSerializer)
