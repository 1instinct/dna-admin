# Saltea Store Setup
# Run: rake db:seed:011_saltea_store

puts "=== Setting up Saltea Store ==="

# 1. Create Saltea store
saltea_store = Spree::Store.find_or_create_by!(code: 'saltea') do |store|
  store.name = 'Saltea'
  store.url = 'saltea.co'
  store.mail_from_address = 'aaron@saltea.co'
  store.default_currency = 'USD'
  store.default = false
  store.seo_title = 'Saltea — Lightly Salted Teas'
  store.meta_description = 'Fresh, lightly salted teas made with real ingredients. The Caribbean Sea, The Rio Grande, The Finger Lakes.'
  store.customer_support_email = 'aaron@saltea.co'
  store.contact_phone = '+1-718-314-0730'
  store.default_locale = 'en'
  store.supported_locales = 'en'
  store.supported_currencies = 'USD'
  store.facebook = 'saltea.drinks'
  store.twitter = 'drinksaltea'
  store.instagram = 'saltea.co'
end
puts "  Store created: #{saltea_store.name} (id: #{saltea_store.id}, code: #{saltea_store.code})"

# 2. Create taxonomy
taxonomy = Spree::Taxonomy.find_or_create_by!(name: 'Saltea Flavors', store: saltea_store)
root_taxon = taxonomy.root
puts "  Taxonomy created: #{taxonomy.name}"

all_teas = Spree::Taxon.find_or_create_by!(name: 'All Teas', taxonomy: taxonomy, parent: root_taxon)
signature = Spree::Taxon.find_or_create_by!(name: 'Signature Blends', taxonomy: taxonomy, parent: root_taxon)
puts "  Taxons: #{all_teas.name}, #{signature.name}"

# 3. Create shipping category
shipping_cat = Spree::ShippingCategory.find_or_create_by!(name: 'Bottled Tea')
puts "  Shipping category: #{shipping_cat.name}"

# 4. Create products
products_data = [
  {
    name: 'The Caribbean Sea',
    slug: 'the-caribbean-sea',
    description: 'Fresh strawberries, dried rose petals, hibiscus tea, a touch of pure himalayan crystal sea salt, and a touch of pure cane sugar.',
    price: 5.99,
    meta_description: 'The Caribbean Sea — strawberry, rose, and hibiscus salted tea by Saltea.'
  },
  {
    name: 'The Rio Grande',
    slug: 'the-rio-grande',
    description: 'Fresh lemons, fresh mint, a touch of pure himalayan crystal sea salt, and a touch of pure cane sugar.',
    price: 5.99,
    meta_description: 'The Rio Grande — lemon and mint salted tea by Saltea.'
  },
  {
    name: 'The Finger Lakes',
    slug: 'the-finger-lakes',
    description: 'Fresh green apples, fresh rosemary, jasmine green tea, a touch of pure himalayan crystal sea salt, and a touch of pure cane sugar.',
    price: 5.99,
    meta_description: 'The Finger Lakes — green apple, rosemary, and jasmine green tea by Saltea.'
  }
]

products_data.each do |data|
  product = Spree::Product.find_or_initialize_by(slug: data[:slug])
  product.assign_attributes(
    name: data[:name],
    description: data[:description],
    price: data[:price],
    meta_description: data[:meta_description],
    available_on: Time.current,
    shipping_category: shipping_cat,
    status: 'active'
  )
  product.save!

  # Associate product with Saltea store
  unless product.stores.include?(saltea_store)
    product.stores << saltea_store
  end

  # Associate with taxons
  [all_teas, signature].each do |taxon|
    unless product.taxons.include?(taxon)
      product.taxons << taxon
    end
  end

  puts "  Product created: #{product.name} ($#{product.price}) [#{product.slug}]"
end

puts ""
puts "=== Saltea Store Setup Complete ==="
puts "  Store URL: #{saltea_store.url}"
puts "  Store Code: #{saltea_store.code}"
puts "  Products: #{Spree::Product.joins(:stores).where(spree_stores: { id: saltea_store.id }).count}"
puts ""
puts "  Next: Generate API token in rails console:"
puts "    token = Spree::OauthAccessToken.create!(scopes: 'storefront')"
puts "    puts token.token"
