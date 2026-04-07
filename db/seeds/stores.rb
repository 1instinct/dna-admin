# db/seeds/stores.rb
#
# Seeds 5 Spree::Store records for Cntrl+ multi-market setup.
# Idempotent: uses find_or_initialize_by on store code.

STORES = [
  {
    code: "cntrl-en",
    name: "Cntrl+ (US)",
    url: ENV.fetch("STORE_URL_EN", "localhost:3000"),
    default_locale: "en",
    default_currency: "USD",
    supported_currencies: "USD",
    supported_locales: "en",
    default: true
  },
  {
    code: "cntrl-de",
    name: "Cntrl+ (Deutschland)",
    url: ENV.fetch("STORE_URL_DE", "localhost:3000"),
    default_locale: "de",
    default_currency: "EUR",
    supported_currencies: "EUR",
    supported_locales: "de",
    default: false
  },
  {
    code: "cntrl-fr",
    name: "Cntrl+ (France)",
    url: ENV.fetch("STORE_URL_FR", "localhost:3000"),
    default_locale: "fr",
    default_currency: "EUR",
    supported_currencies: "EUR",
    supported_locales: "fr",
    default: false
  },
  {
    code: "cntrl-it",
    name: "Cntrl+ (Italia)",
    url: ENV.fetch("STORE_URL_IT", "localhost:3000"),
    default_locale: "it",
    default_currency: "EUR",
    supported_currencies: "EUR",
    supported_locales: "it",
    default: false
  },
  {
    code: "cntrl-es",
    name: "Cntrl+ (Espana)",
    url: ENV.fetch("STORE_URL_ES", "localhost:3000"),
    default_locale: "es",
    default_currency: "EUR",
    supported_currencies: "EUR",
    supported_locales: "es",
    default: false
  }
].freeze

puts "Seeding Spree::Store records..."

STORES.each do |attrs|
  store = Spree::Store.find_or_initialize_by(code: attrs[:code])
  store.assign_attributes(attrs)
  store.save!
  puts "  #{store.default? ? '* ' : '  '}#{store.code} — #{store.name} (#{store.default_currency})"
end

# Ensure only one default store
Spree::Store.where.not(code: "cntrl-en").update_all(default: false)

puts "Done. #{Spree::Store.count} stores configured."
