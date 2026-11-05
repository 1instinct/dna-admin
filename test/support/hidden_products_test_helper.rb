# Shared setup for the tests that keep unavailable products away from the public.
module HiddenProductsTestHelper
  NOT_FOUND_BODY = { 'error' => 'The resource you were looking for could not be found.' }.freeze

  # One visible product and one for each way of being unavailable, all with an image, a video
  # and a property, all in the same taxon. "Secret" appears only in the hidden products' data.
  def build_catalog
    media_store
    taxonomy = Spree::Taxonomy.create!(name: 'Collections')
    @taxon = Spree::Taxon.create!(name: 'Featured', parent: taxonomy.root, taxonomy: taxonomy)

    @visible = catalog_product('Visible Thing', 1.day.ago, 'VISIBLE-SKU')
    @null_on = catalog_product('Secret Null', nil, 'SECRET-NULL-SKU')
    @future = catalog_product('Secret Future', 1.week.from_now, 'SECRET-FUTURE-SKU')
    @discontinued = catalog_product('Secret Discontinued', 1.month.ago, 'SECRET-DISCONTINUED-SKU')
    @discontinued.update!(discontinue_on: 1.hour.ago)
    @deleted = catalog_product('Secret Deleted', 1.day.ago, 'SECRET-DELETED-SKU')
    @deleted_id = @deleted.id
    @deleted.destroy!
  end

  def catalog_product(name, available_on, sku)
    product = media_product(name: name, available_on: available_on)
    product.master.update!(sku: sku)
    media_image(product.master, ShopMediaTestHelper::PNG_BYTES, "#{sku}.png", 'image/png', width: 1, height: 1)
    media_video(product)
    product.set_property('colour', "#{name} property")
    product.taxons << @taxon
    product
  end

  # The hidden products that still exist as far as the default scope goes.
  def hidden_products
    { 'null available_on' => @null_on, 'future available_on' => @future, 'discontinued' => @discontinued }
  end

  def hidden_ids
    [@null_on.id, @future.id, @discontinued.id, @deleted_id]
  end

  # A JSON:API "links" block echoes the query string back, which proves nothing.
  def assert_nothing_secret
    body = begin
      parsed = JSON.parse(response.body)
      parsed.is_a?(Hash) ? parsed.except('links').to_json : response.body
    rescue JSON::ParserError
      response.body
    end
    refute_match(/secret/i, body, "#{request.fullpath} exposed a hidden product")
  end

  def assert_hidden_404
    assert_response :not_found, "#{request.fullpath} answered #{response.status}: #{response.body[0, 200]}"
    assert_equal NOT_FOUND_BODY, JSON.parse(response.body)
  end

  def api_user(admin: false)
    user = Spree.user_class.create!(email: "hidden-#{SecureRandom.hex(4)}@example.com", password: 'password123')
    user.generate_spree_api_key!
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin') if admin
    user
  end

  def api_key(user)
    { 'X-Spree-Token' => user.spree_api_key }
  end

  def oauth(user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: '')
    token = record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token
    { 'Authorization' => "Bearer #{token}" }
  end
end

ActiveSupport::TestCase.include(HiddenProductsTestHelper)
