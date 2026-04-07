# Load Spree API V2 Storefront decorators
Rails.application.config.to_prepare do
  Dir.glob(Rails.root.join('app', 'controllers', 'spree', 'api', 'v2', 'storefront', '*_decorator.rb')).each do |decorator|
    require_dependency decorator
  end
  load Rails.root.join("app/serializers/spree/api/v2/storefront/product_serializer_decorator.rb")
  load Rails.root.join("app/serializers/spree/api/v2/storefront/account_serializer_decorator.rb")
end
