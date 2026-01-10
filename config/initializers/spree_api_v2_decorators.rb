# Load Spree API V2 Storefront decorators
Rails.application.config.to_prepare do
  Dir.glob(Rails.root.join('app', 'controllers', 'spree', 'api', 'v2', 'storefront', '*_decorator.rb')).each do |decorator|
    require_dependency decorator
  end
end
