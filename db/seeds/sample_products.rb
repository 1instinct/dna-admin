# db/seeds/sample_products.rb
#
# Dev-only sample products for multi-store testing.
# Run after stores.rb seed.

return unless Rails.env.development?

puts "Seeding sample products for multi-store testing..."

shipping_category = Spree::ShippingCategory.first_or_create!(name: "Default")

SAMPLE_PRODUCTS = {
  "cntrl-en" => [
    { name: "Pessary Starter Kit", price: 149.99, currency: "USD", sku: "PSK-US-001" },
    { name: "Pessary Device", price: 79.99, currency: "USD", sku: "PD-US-001" },
    { name: "Pessary Care Kit", price: 29.99, currency: "USD", sku: "PCK-US-001" }
  ],
  "cntrl-de" => [
    { name: "Pessar Starter-Set", price: 139.99, currency: "EUR", sku: "PSK-DE-001" },
    { name: "Pessar-Geraet", price: 74.99, currency: "EUR", sku: "PD-DE-001" },
    { name: "Pessar-Pflegeset", price: 27.99, currency: "EUR", sku: "PCK-DE-001" }
  ],
  "cntrl-fr" => [
    { name: "Kit de demarrage Pessaire", price: 139.99, currency: "EUR", sku: "PSK-FR-001" },
    { name: "Dispositif Pessaire", price: 74.99, currency: "EUR", sku: "PD-FR-001" },
    { name: "Kit d'entretien Pessaire", price: 27.99, currency: "EUR", sku: "PCK-FR-001" }
  ],
  "cntrl-it" => [
    { name: "Kit iniziale Pessario", price: 139.99, currency: "EUR", sku: "PSK-IT-001" },
    { name: "Dispositivo Pessario", price: 74.99, currency: "EUR", sku: "PD-IT-001" },
    { name: "Kit cura Pessario", price: 27.99, currency: "EUR", sku: "PCK-IT-001" }
  ],
  "cntrl-es" => [
    { name: "Kit de inicio Pesario", price: 139.99, currency: "EUR", sku: "PSK-ES-001" },
    { name: "Dispositivo Pesario", price: 74.99, currency: "EUR", sku: "PD-ES-001" },
    { name: "Kit de cuidado Pesario", price: 27.99, currency: "EUR", sku: "PCK-ES-001" }
  ]
}.freeze

SAMPLE_PRODUCTS.each do |store_code, products|
  store = Spree::Store.find_by!(code: store_code)
  currency = products.first[:currency]

  products.each do |attrs|
    product = Spree::Product.find_or_initialize_by(name: attrs[:name])
    product.assign_attributes(
      price: attrs[:price],
      shipping_category: shipping_category,
      available_on: 1.day.ago
    )
    product.save!

    product.stores << store unless product.stores.include?(store)

    # Set price in correct currency
    master = product.master
    master.sku = attrs[:sku]
    master.save!

    master.prices.find_or_create_by!(currency: currency) do |p|
      p.amount = attrs[:price]
    end

    puts "  #{store_code}: #{attrs[:name]} — #{currency} #{attrs[:price]}"
  end
end

puts "Done. Sample products seeded for all stores."
