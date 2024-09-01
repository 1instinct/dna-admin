# Spree::Core::Engine.load_seed if defined?(Spree::Core)
# Spree::Auth::Engine.load_seed if defined?(Spree::Auth)

# 10.times do |i|
#   Spree::Page.create!(
#     title: Faker::Lorem.word.capitalize,
#     body: Faker::Lorem.paragraph,
#     slug: Faker::Internet.slug,
#     created_at: Time.now,
#     updated_at: Time.now,
#     show_in_header: [true, false].sample,
#     foreign_link: Faker::Internet.url,
#     position: i,
#     visible: [true, false].sample,
#     meta_keywords: Faker::Lorem.words(number: 5).join(', '), # Correct usage of words method
#     meta_description: Faker::Lorem.sentence,
#     layout: ['page', 'content'].sample,
#     show_in_sidebar: [true, false].sample,
#     meta_title: Faker::Lorem.sentence,
#     render_layout_as_partial: [true, false].sample,
#     show_in_footer: [true, false].sample
#   )
# end