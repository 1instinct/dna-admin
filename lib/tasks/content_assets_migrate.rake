# frozen_string_literal: true

namespace :content_assets do
  desc "Migrate existing image URLs from homepage sections and pages into ContentAsset records"
  task migrate_existing: :environment do
    require 'down'

    created = 0
    skipped = 0
    failed  = 0

    puts "=== Migrating Homepage Section Images ==="

    HomepageSection.find_each do |section|
      settings = section.settings
      next unless settings.is_a?(Hash)

      changed = false
      settings.each do |key, value|
        if value.is_a?(String) && image_url?(value) && !already_proxied?(value)
          asset = download_and_create(value)
          if asset
            settings[key] = asset.original_url
            changed = true
            created += 1
            puts "  [#{section.title}] #{key}: migrated"
          else
            failed += 1
          end
        end

        if value.is_a?(Array)
          value.each_with_index do |item, idx|
            next unless item.is_a?(Hash)
            item.each do |ik, iv|
              if iv.is_a?(String) && image_url?(iv) && !already_proxied?(iv)
                asset = download_and_create(iv)
                if asset
                  settings[key][idx][ik] = asset.original_url
                  changed = true
                  created += 1
                  puts "  [#{section.title}] #{key}[#{idx}].#{ik}: migrated"
                else
                  failed += 1
                end
              end
            end
          end
        end
      end

      section.update_column(:settings, settings) if changed
    end

    puts "\n=== Migrating CMS Page Images ==="

    Spree::Page.find_each do |page|
      body = page.body.to_s
      next if body.blank?

      begin
        sections = JSON.parse(body)
        next unless sections.is_a?(Array)

        changed = false
        sections.each_with_index do |section, si|
          next unless section.is_a?(Hash) && section["content"].is_a?(Hash)
          section["content"].each do |key, val|
            if val.is_a?(String) && image_url?(val) && !already_proxied?(val)
              asset = download_and_create(val)
              if asset
                sections[si]["content"][key] = asset.original_url
                changed = true
                created += 1
                puts "  [#{page.slug}] section[#{si}].#{key}: migrated"
              else
                failed += 1
              end
            end

            if val.is_a?(Array)
              val.each_with_index do |item, idx|
                next unless item.is_a?(Hash)
                item.each do |ik, iv|
                  if iv.is_a?(String) && image_url?(iv) && !already_proxied?(iv)
                    asset = download_and_create(iv)
                    if asset
                      sections[si]["content"][key][idx][ik] = asset.original_url
                      changed = true
                      created += 1
                      puts "  [#{page.slug}] section[#{si}].#{key}[#{idx}].#{ik}: migrated"
                    else
                      failed += 1
                    end
                  end
                end
              end
            end
          end
        end

        page.update_column(:body, sections.to_json) if changed
      rescue JSON::ParserError
        skipped += 1
      end
    end

    puts "\n=== Migration Summary ==="
    puts "  Created: #{created}"
    puts "  Skipped: #{skipped}"
    puts "  Failed:  #{failed}"
    puts "Done."
  end
end

def image_url?(str)
  str.match?(/\.(png|jpe?g|webp|gif|svg)(\?|$)/i) ||
    str.include?('/cdn/shop/files/')
end

def already_proxied?(str)
  str.include?('/rails/active_storage/')
end

def download_and_create(url)
  if url.start_with?('/')
    puts "    WARN: local path #{url} — cannot download, needs manual upload"
    return nil
  end

  url = "https:#{url}" if url.start_with?('//')
  url = "https://#{url}" unless url.start_with?('http')

  file = Down.download(url, max_size: 10 * 1024 * 1024)
  filename = File.basename(URI.parse(url).path)

  asset = ContentAsset.new(
    alt_text: filename.sub(/\.[^.]+$/, '').tr('-_', ' ').titleize,
    tag: 'migrated'
  )
  asset.file.attach(
    io: file,
    filename: filename,
    content_type: file.content_type
  )

  if asset.save
    asset
  else
    puts "    ERROR: #{asset.errors.full_messages.join(', ')}"
    nil
  end
rescue Down::Error, OpenURI::HTTPError, URI::InvalidURIError => e
  puts "    ERROR downloading #{url}: #{e.message}"
  nil
end
