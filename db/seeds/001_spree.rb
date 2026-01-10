Spree::Core::Engine.load_seed if defined?(Spree::Core)
Spree::Auth::Engine.load_seed if defined?(Spree::Auth)

pages = [
  { title: 'About Us', body: 'Learn about our story, mission, and the team behind our brand.' },
  { title: 'Contact', body: 'Get in touch with our customer service team. We are here to help!' },
  { title: 'Shipping & Returns', body: 'Information about our shipping policies, delivery times, and return process.' },
  { title: 'Privacy Policy', body: 'How we collect, use, and protect your personal information.' },
  { title: 'Terms & Conditions', body: 'Terms of service and conditions for using our website and services.' },
  { title: 'FAQ', body: 'Frequently asked questions about orders, products, and our services.' },
  { title: 'Size Guide', body: 'Find your perfect fit with our comprehensive sizing charts and measurement guide.' },
  { title: 'Our Story', body: 'Discover the journey of our brand and what makes us unique.' }
]

pages.each_with_index do |page_data, i|
  Spree::Page.create!(
    title: page_data[:title],
    body: page_data[:body],
    slug: page_data[:title].parameterize,
    created_at: Time.now,
    updated_at: Time.now,
    show_in_header: [true, false].sample,
    foreign_link: nil,
    position: i,
    visible: true,
    meta_keywords: page_data[:title].downcase,
    meta_description: page_data[:body],
    layout: 'page',
    show_in_sidebar: false,
    meta_title: page_data[:title],
    render_layout_as_partial: false,
    show_in_footer: [true, false].sample
  )
end