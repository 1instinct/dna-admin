# Spree::Product.publicly_visible: the products the public may see. The SQL twin of
# Product#available?, so it has no price condition, unlike Spree's Product.available, whose join
# on prices would change what a product with no price answers.
#
# It's a filter for public endpoints, not a default scope: the admin, the checkout and scripts
# keep seeing every product. Loaded by the to_prepare decorator glob, so it must be safe to load
# more than once: extending with the same module again changes nothing.
module Spree
  module ProductPublicVisibilityDecorator
    module ClassMethods
      def publicly_visible
        now = Time.current
        where("#{quoted_table_name}.available_on <= ?", now).
          where("#{quoted_table_name}.discontinue_on IS NULL OR #{quoted_table_name}.discontinue_on > ?", now).
          where("#{quoted_table_name}.deleted_at IS NULL")
      end
    end

    def self.prepended(base)
      base.extend(ClassMethods)
    end
  end
end

Spree::Product.prepend(Spree::ProductPublicVisibilityDecorator)
