Spree::Core::Engine.load_seed if defined?(Spree::Core)
Spree::Auth::Engine.load_seed if defined?(Spree::Auth)

10.times do |i|
  Spree::Page.create!(
    title: FFaker::Lorem.word.capitalize,
    body: FFaker::Lorem.paragraph,
    slug: FFaker::Internet.slug,
    created_at: Time.now,
    updated_at: Time.now,
    show_in_header: [true, false].sample,
    foreign_link: FFaker::Internet.uri('https'),
    position: i,
    visible: [true, false].sample,
    meta_keywords: FFaker::Lorem.words(5).join(', '),
    meta_description: FFaker::Lorem.sentence,
    layout: ['page', 'content'].sample,
    show_in_sidebar: [true, false].sample,
    meta_title: FFaker::Lorem.sentence,
    render_layout_as_partial: [true, false].sample,
    show_in_footer: [true, false].sample
  )
end