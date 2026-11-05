# frozen_string_literal: true

namespace :content_assets do
  desc "Migrate existing image URLs from homepage sections and pages into ContentAsset records"
  task migrate_existing: :environment do
    require 'net/http'

    # The rewritten URLs are read by the storefront, which runs on another host,
    # so they must be absolute. Refuse to write relative paths.
    if Rails.application.routes.default_url_options[:host].blank?
      abort "content_assets:migrate_existing: no host configured for URL generation. " \
            "Set Rails.application.routes.default_url_options (host, and protocol/port if needed) " \
            "for #{Rails.env} so absolute image URLs can be written."
    end

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
            settings[key] = absolute_asset_url(asset)
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
                  settings[key][idx][ik] = absolute_asset_url(asset)
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
                sections[si]["content"][key] = absolute_asset_url(asset)
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
                      sections[si]["content"][key][idx][ik] = absolute_asset_url(asset)
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

  io, content_type = fetch_remote_file(url)
  filename = File.basename(URI.parse(url).path)

  asset = ContentAsset.new(
    alt_text: filename.sub(/\.[^.]+$/, '').tr('-_', ' ').titleize,
    tag: 'migrated'
  )
  asset.file.attach(
    io: io,
    filename: filename,
    content_type: content_type
  )

  if asset.save
    asset
  else
    puts "    ERROR: #{asset.errors.full_messages.join(', ')}"
    nil
  end
rescue ContentAssetDownloadError, URI::Error, SocketError, Timeout::Error,
       SystemCallError, IOError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
  puts "    ERROR downloading #{url}: #{e.message}"
  nil
end

class ContentAssetDownloadError < StandardError; end

# Downloads an http(s) URL into memory, following up to `redirects` redirects
# and refusing anything over ContentAsset::MAX_FILE_SIZE.
# Returns [StringIO, content_type].
def fetch_remote_file(url, redirects = 5)
  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) && uri.host.present?
    raise ContentAssetDownloadError, "only http(s) URLs can be downloaded"
  end

  max_size = ContentAsset::MAX_FILE_SIZE
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                  open_timeout: 10, read_timeout: 30) do |http|
    http.request(Net::HTTP::Get.new(uri)) do |response|
      case response
      when Net::HTTPRedirection
        raise ContentAssetDownloadError, "too many redirects" if redirects <= 0
        location = response['location'].to_s
        raise ContentAssetDownloadError, "redirect without location" if location.empty?
        return fetch_remote_file(URI.join(uri.to_s, location).to_s, redirects - 1)
      when Net::HTTPSuccess
        if response['content-length'].to_i > max_size
          raise ContentAssetDownloadError, "file is larger than #{max_size / 1.megabyte}MB"
        end

        io = StringIO.new(String.new)
        response.read_body do |chunk|
          io.write(chunk)
          if io.size > max_size
            raise ContentAssetDownloadError, "file is larger than #{max_size / 1.megabyte}MB"
          end
        end
        io.rewind
        return [io, response['content-type'].to_s.split(';').first.to_s.strip.presence]
      else
        raise ContentAssetDownloadError, "HTTP #{response.code}"
      end
    end
  end
end

# Absolute proxy URL, built from Rails.application.routes.default_url_options.
def absolute_asset_url(asset)
  Rails.application.routes.url_helpers.rails_storage_proxy_url(asset.file)
end
