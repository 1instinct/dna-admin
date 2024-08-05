module Spree
    module ImageDecorator
        module ClassMethods
            def styles
                {
                    mini: '48x48>',
                    small: '100x100>',
                    product: '240x240>',
                    large: '600x600>',
                    xl: '1000x1000>',
                    widescreen: '1600x900>',
                    portrait: '900x1600>'
                }
            end
        end
    
        def self.prepended(base)
            base.singleton_class.prepend ClassMethods
        end
    end

    Spree::Image.prepend(Spree::ImageDecorator)
end