# Spree::Product has_many :videos (Spree::ProductVideo). Loaded by the to_prepare decorator
# glob, so it must be safe to load more than once: prepending an already-prepended module is a
# no-op, and a reloaded Spree::Product gets the association again through `prepended`.
module Spree
  module ProductVideosDecorator
    def self.prepended(base)
      base.has_many :videos, -> { order(:position) }, class_name: 'Spree::ProductVideo',
                                                     inverse_of: :product, dependent: :destroy
    end
  end
end

Spree::Product.prepend(Spree::ProductVideosDecorator)
