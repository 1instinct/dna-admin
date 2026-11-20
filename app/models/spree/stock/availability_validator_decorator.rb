# A cart can't gain a line for a product that isn't available. Spree refuses a quantity above
# zero already, but its message names the product, and it lets a quantity of zero through, which
# hands the whole product (images included) to anyone who knows a variant id.
#
# Only a new line, or a line being pointed at another variant, is judged here. A line that was
# already in a cart when its product was hidden goes on to Spree's validator unchanged.
module Spree
  module Stock
    module AvailabilityValidatorDecorator
      def validate(line_item)
        variant = line_item.variant
        if variant && (line_item.new_record? || line_item.variant_id_changed?) && !variant.available?
          line_item.errors.add(:base, 'This item is not available.')
          return
        end

        super
      end
    end
  end
end

# Referenced directly so the classic autoloader loads the class: a `defined?` guard is nil for a
# constant that hasn't been autoloaded yet.
unless Spree::Stock::AvailabilityValidator < Spree::Stock::AvailabilityValidatorDecorator
  Spree::Stock::AvailabilityValidator.prepend(Spree::Stock::AvailabilityValidatorDecorator)
end
