# Shared helpers for the profiles module tests.
module ProfilesTestHelper
  # Swap in small word lists so tests don't depend on the shipped YAML.
  def with_moderation_lists(reserved: %w[admin support], blocked: %w[badword])
    Profiles.config.reserved_handles = Set.new(reserved)
    Profiles.config.blocked_terms = blocked
    yield
  ensure
    Profiles.reset_config!
  end

  def make_admin(user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  def token_for(user)
    record = Doorkeeper.config.access_token_model.create!(resource_owner_id: user.id, expires_in: 3600, scopes: '')
    record.respond_to?(:plaintext_token) && record.plaintext_token ? record.plaintext_token : record.token
  end

  def bearer(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def auth(user)
    bearer(token_for(user))
  end

  def json
    JSON.parse(response.body)
  end

  def fixture_upload(name, type)
    Rack::Test::UploadedFile.new(Rails.root.join('test', 'fixtures', 'files', name), type)
  end

  def bytes_upload(bytes, type, name = 'upload.bin')
    file = Tempfile.new(['upload', File.extname(name)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end

  def create_public_favorite(user, name: 'Fav Product', price: 29)
    store = Spree::Store.default
    unless store.persisted?
      store = Spree::Store.create!(name: 'Test Store', url: 'test.example.com', code: "test-#{SecureRandom.hex(3)}",
                                   mail_from_address: 'store@example.com', default_currency: 'USD', default: true)
    end
    shipping_category = Spree::ShippingCategory.create!(name: "prof-#{SecureRandom.hex(4)}")
    product = Spree::Product.new(name: name, price: price, shipping_category: shipping_category)
    product.stores << store if product.respond_to?(:stores)
    product.save!
    Favorite.create!(user: user, variant: product.master, is_public: true)
  end
end

ActiveSupport::TestCase.include(ProfilesTestHelper)
