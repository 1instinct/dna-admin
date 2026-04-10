require "fileutils"
require "json"
require "shopify_extract/query_loader"

module ShopifyExtract
  class TopologyResolver
    def initialize(client, output_dir: nil)
      @client = client
      @output_dir = output_dir
    end

    def call
      response = @client.query(QueryLoader.load("topology"))
      data = response.fetch("data")

      shop_locales = data.dig("shop", "shopLocales") || []
      markets = (data.dig("markets", "edges") || []).map { |e| e["node"] }

      locale_to_market = build_locale_to_market(shop_locales, markets)

      topology = {
        shop_locales: shop_locales,
        markets: markets.map { |m| simplify_market(m) },
        locale_to_market: locale_to_market
      }

      persist!(topology) if @output_dir
      topology
    end

    private

    def build_locale_to_market(shop_locales, markets)
      mapping = {}
      shop_locales.each do |sl|
        locale = sl["locale"]
        mapping[locale] = find_market_for_locale(locale, markets)
      end
      mapping
    end

    def find_market_for_locale(locale, markets)
      matched = markets.find do |m|
        urls = m.dig("webPresence", "rootUrls") || []
        urls.any? { |u| u["locale"] == locale }
      end
      matched ||= markets.find { |m| m["primary"] }
      return nil unless matched

      country_code = country_for_locale(locale, matched)
      {
        "market_id" => matched["id"],
        "market_name" => matched["name"],
        "country_code" => country_code,
        "currency" => currency_for_country(country_code)
      }
    end

    def country_for_locale(locale, market)
      # If the market has multiple countries and locale is one of them (DE, FR, IT, ES),
      # prefer the matching country. Otherwise use the first region.
      countries = (market.dig("regions", "edges") || []).map { |e| e.dig("node", "code") }
      locale_upper = locale.upcase
      return locale_upper if countries.include?(locale_upper)
      countries.first
    end

    def currency_for_country(country)
      { "US" => "USD", "DE" => "EUR", "FR" => "EUR", "IT" => "EUR", "ES" => "EUR" }[country] || "USD"
    end

    def simplify_market(m)
      {
        "id" => m["id"],
        "name" => m["name"],
        "primary" => m["primary"],
        "countries" => (m.dig("regions", "edges") || []).map { |e| e.dig("node", "code") }
      }
    end

    def persist!(topology)
      FileUtils.mkdir_p(File.join(@output_dir, "_meta"))
      File.write(
        File.join(@output_dir, "_meta", "topology.json"),
        JSON.pretty_generate(topology)
      )
    end
  end
end
