# Seed one empty app_links section so the store URLs can be filled in from the admin
puts "Creating app links section..."

HomepageSection.find_or_create_by(section_type: 'app_links') do |section|
  section.title = "App Store Links"
  section.position = 0
  section.is_visible = true
  section.settings = { 'ios_url' => '', 'android_url' => '' }
end

puts "- #{HomepageSection.by_type('app_links').count} app_links section(s)"
