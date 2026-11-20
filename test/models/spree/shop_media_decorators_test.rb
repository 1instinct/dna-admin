require 'test_helper'

# config/application.rb loads every *_decorator*.rb in to_prepare (with `load` when classes
# reload), so the media decorators must be harmless when loaded again.
class Spree::ShopMediaDecoratorsTest < ActiveSupport::TestCase
  DECORATORS = %w[
    app/models/spree/image_media_decorator.rb
    app/models/spree/product_videos_decorator.rb
    app/serializers/spree/v2/storefront/image_serializer_decorator.rb
    app/serializers/spree/v2/storefront/product_serializer_decorator.rb
    app/controllers/spree/api/v2/storefront/products_controller_decorator.rb
  ].freeze

  test 'loading the decorators again changes nothing' do
    image_attrs = Spree::V2::Storefront::ImageSerializer.attributes_to_serialize.keys
    product_rels = Spree::V2::Storefront::ProductSerializer.relationships_to_serialize.keys

    2.times { DECORATORS.each { |path| load Rails.root.join(path).to_s } }

    assert_equal image_attrs, Spree::V2::Storefront::ImageSerializer.attributes_to_serialize.keys
    assert_equal product_rels, Spree::V2::Storefront::ProductSerializer.relationships_to_serialize.keys
    assert_equal 1, Spree::Image.ancestors.count(Spree::ImageMediaDecorator)
    assert_equal 1, Spree::Product.ancestors.count(Spree::ProductVideosDecorator)
    assert_equal 1, Spree::Api::V2::Storefront::ProductsController.ancestors.
      count(Spree::Api::V2::Storefront::ProductsControllerDecorator)
    assert_equal 'Spree::ProductVideo', Spree::Product.reflect_on_association(:videos).class_name
  end

  test 'the image serializer keeps its stock attributes' do
    keys = Spree::V2::Storefront::ImageSerializer.attributes_to_serialize.keys
    assert_equal %i[viewable_type viewable_id styles], keys.first(3)
    refute_includes keys, :original_url
  end
end
