require "shopify_extract/extractor"

namespace :extract do
  desc "Run full extraction for all locales (RESOURCE=products|collections|menus|media, LOCALE=en|de|…, FORCE=1, MIGRATE=1)"
  task :all => :environment do
    resource = ENV["RESOURCE"]
    locale = ENV["LOCALE"]
    force = ENV["FORCE"] == "1"
    migrate = ENV["MIGRATE"] == "1"

    ShopifyExtract::Extractor.new.call(resource: resource, locale: locale, force: force, migrate: migrate)
  end

  desc "Extract products (requires LOCALE=)"
  task :products => :environment do
    locale = ENV.fetch("LOCALE")
    ShopifyExtract::Extractor.new.call(resource: "products", locale: locale, force: ENV["FORCE"] == "1")
  end

  desc "Extract collections (requires LOCALE=)"
  task :collections => :environment do
    locale = ENV.fetch("LOCALE")
    ShopifyExtract::Extractor.new.call(resource: "collections", locale: locale, force: ENV["FORCE"] == "1")
  end

  desc "Extract menus (requires LOCALE=)"
  task :menus => :environment do
    locale = ENV.fetch("LOCALE")
    ShopifyExtract::Extractor.new.call(resource: "menus", locale: locale, force: ENV["FORCE"] == "1")
  end

  desc "Extract media (requires LOCALE=)"
  task :media => :environment do
    locale = ENV.fetch("LOCALE")
    ShopifyExtract::Extractor.new.call(resource: "media", locale: locale)
  end

  desc "Reset extracted/ directory (asks confirmation)"
  task :reset => :environment do
    output_dir = Rails.application.config.shopify_extract&.output_dir
    abort "Not configured" unless output_dir
    print "Delete everything in #{output_dir}? [yes/NO] "
    answer = STDIN.gets.strip
    if answer == "yes"
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)
      puts "Done."
    else
      puts "Aborted."
    end
  end
end
