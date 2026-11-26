# Reviews, rating stats and questions on Spree::Product, and store reviews on Spree::Store.
# Loaded by the to_prepare decorator glob; prepending the same module again changes nothing.
module Spree
  module ProductReviewsDecorator
    def self.prepended(base)
      base.has_many :reviews, as: :reviewable, class_name: 'Spree::Review', dependent: :destroy
      base.has_many :review_stats, as: :reviewable, class_name: 'Spree::ReviewStat', dependent: :delete_all
      base.has_many :questions, class_name: 'Spree::ProductQuestion', dependent: :destroy
    end
  end

  module StoreReviewsDecorator
    def self.prepended(base)
      base.has_many :reviews, as: :reviewable, class_name: 'Spree::Review', dependent: :destroy
      base.has_many :review_stats, as: :reviewable, class_name: 'Spree::ReviewStat', dependent: :delete_all
    end
  end
end

Spree::Product.prepend(Spree::ProductReviewsDecorator)
Spree::Store.prepend(Spree::StoreReviewsDecorator)
