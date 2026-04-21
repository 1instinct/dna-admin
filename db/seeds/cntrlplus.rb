# frozen_string_literal: true
#
# db/seeds/cntrlplus.rb
#
# Seeds ALL Cntrl+-specific data: stores, products, menus, homepage sections,
# CMS pages, landing pages, simple pages, blog posts.
# Idempotent where possible (find_or_create_by).
#

require 'open-uri'

# ---------------------------------------------------------------------------
# Helper: attach product image from a URL (non-blocking on failure)
# ---------------------------------------------------------------------------
def attach_image_from_url(record, url, filename, alt = nil)
  url = "https:#{url}" if url.start_with?("//")
  uri = URI.parse(url)
  downloaded = uri.open(open_timeout: 10, read_timeout: 20)
  record.images.create!(
    attachment: { io: downloaded, filename: filename, content_type: downloaded.content_type },
    alt: alt || record.try(:name) || filename
  )
  puts "  ✓ Attached #{filename}"
rescue StandardError => e
  puts "  ⚠ Failed to download #{url}: #{e.message} — skipping image"
end

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  1. STORES                                                                ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seeding Stores ==="

STORES = [
  { code: "cntrl-en", name: "Cntrl+ (US)",          url: ENV.fetch("STORE_URL_EN", "localhost:3000"), default_locale: "en", default_currency: "USD", supported_currencies: "USD", supported_locales: "en", default: true },
  { code: "cntrl-de", name: "Cntrl+ (Deutschland)", url: ENV.fetch("STORE_URL_DE", "localhost:3000"), default_locale: "de", default_currency: "EUR", supported_currencies: "EUR", supported_locales: "de", default: false },
  { code: "cntrl-fr", name: "Cntrl+ (France)",      url: ENV.fetch("STORE_URL_FR", "localhost:3000"), default_locale: "fr", default_currency: "EUR", supported_currencies: "EUR", supported_locales: "fr", default: false },
  { code: "cntrl-it", name: "Cntrl+ (Italia)",      url: ENV.fetch("STORE_URL_IT", "localhost:3000"), default_locale: "it", default_currency: "EUR", supported_currencies: "EUR", supported_locales: "it", default: false },
  { code: "cntrl-es", name: "Cntrl+ (Espana)",      url: ENV.fetch("STORE_URL_ES", "localhost:3000"), default_locale: "es", default_currency: "EUR", supported_currencies: "EUR", supported_locales: "es", default: false },
].freeze

STORES.each do |attrs|
  store = Spree::Store.find_or_initialize_by(code: attrs[:code])
  store.assign_attributes(attrs.merge(mail_from_address: "support@cntrlplus.com"))
  store.save!
  puts "  #{store.default? ? '★' : ' '} #{store.code} — #{store.name}"
end
Spree::Store.where.not(code: "cntrl-en").update_all(default: false)
puts "  #{Spree::Store.count} stores configured."

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  2. PRODUCTS                                                              ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seeding Products ==="

shipping_cat = Spree::ShippingCategory.find_or_create_by!(name: "Default")
taxonomy     = Spree::Taxonomy.find_or_create_by!(name: "Categories") { |t| t.position = 0 }
bladder_support_taxon = taxonomy.root.children.find_or_create_by!(name: "Bladder Support") do |t|
  t.taxonomy  = taxonomy
  t.permalink = "categories/bladder-support"
end

# --- Starter Kit ---
unless Spree::Product.find_by(slug: "starter-kit")
  starter_kit = Spree::Product.create!(
    name: "Cntrl+ Starter Kit (Rx)",
    slug: "starter-kit",
    description: "The complete Cntrl+ Starter Kit includes three sizes of our reusable bladder support device (Small, Medium, Large), 90 cotton removal strings, and an organic cotton travel bag. Includes a licensed provider review and 12 months of telehealth access. FDA-cleared. FSA/HSA eligible.",
    price: 159.00,
    available_on: Time.current,
    shipping_category: shipping_cat,
    sku: "PES-006"
  )
  starter_kit.requires_consultation = true rescue nil
  starter_kit.save!
  starter_kit.taxons << bladder_support_taxon
  starter_kit.master.stock_items.first&.update(count_on_hand: 100)

  # Product images
  starter_kit_images = [
    ["https://cntrlplus.com/cdn/shop/files/S_Flipped-_transparent.webp?v=1776613352",  "starter-kit-device.webp"],
    ["https://cntrlplus.com/cdn/shop/files/Full_Kit_Black.png?v=1776613352",            "starter-kit-full.png"],
    ["https://cntrlplus.com/cdn/shop/files/C1W-08307.jpg?v=1776613352",                 "starter-kit-lifestyle.jpg"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__All_Sizes.png?v=1776613352",          "starter-kit-all-sizes.png"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__S_Solo.png?v=1776613352",             "starter-kit-small.png"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__M_Solo.png?v=1776613352",             "starter-kit-medium.png"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__L_Solo.png?v=1776613352",             "starter-kit-large.png"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__StarterKit_Can.png?v=1776613352",     "starter-kit-canister.png"],
  ]
  starter_kit_images.each { |url, fn| attach_image_from_url(starter_kit, url, fn) }
  puts "  ✓ Created Starter Kit ($159)"
end

# --- Single Size Replacement ---
unless Spree::Product.find_by(slug: "single-size-replacement")
  # Create the size option type
  size_option = Spree::OptionType.find_or_create_by!(name: "size") do |ot|
    ot.presentation = "Size"
  end
  small_val  = Spree::OptionValue.find_or_create_by!(name: "S", option_type: size_option) { |v| v.presentation = "S (Small)" }
  medium_val = Spree::OptionValue.find_or_create_by!(name: "M", option_type: size_option) { |v| v.presentation = "M (Medium)" }
  large_val  = Spree::OptionValue.find_or_create_by!(name: "L", option_type: size_option) { |v| v.presentation = "L (Large)" }

  replacement = Spree::Product.create!(
    name: "Cntrl+ Single Size Replacement",
    slug: "single-size-replacement",
    description: "Already found your perfect fit? The Cntrl+ Single Size Replacement includes one reusable bladder support device in your chosen size, plus 90 cotton removal strings and an organic cotton travel bag. Designed for all activity levels, light to severe leaks. Washable and reusable for 90+ uses. 12 months free SUI telehealth access.",
    price: 89.00,
    available_on: Time.current,
    shipping_category: shipping_cat,
    sku: "PES-REPL"
  )
  replacement.option_types << size_option
  replacement.taxons << bladder_support_taxon

  # Create size variants
  [
    { sku: "PES-003", option_value: small_val },
    { sku: "PES-004", option_value: medium_val },
    { sku: "PES-005", option_value: large_val },
  ].each do |vdata|
    variant = replacement.variants.create!(
      sku: vdata[:sku],
      price: 89.00,
      option_values: [vdata[:option_value]],
      track_inventory: true
    )
    variant.stock_items.first&.update(count_on_hand: 100)
  end

  # Product images per size
  replacement_images = [
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__S_Solo_87e6e91e-779d-41f1-8346-7a1485542756.png", "replacement-small.png",  "Small Size"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__M_Solo_199107a4-43e4-4663-925f-bb0f9d0b8796.png", "replacement-medium.png", "Medium Size"],
    ["https://cntrlplus.com/cdn/shop/files/Cntrl__L_Solo_c295887f-9ce5-4b58-9040-c1c6763f6060.png", "replacement-large.png",  "Large Size"],
  ]
  replacement_images.each { |url, fn, alt| attach_image_from_url(replacement, url, fn, alt) }
  puts "  ✓ Created Single Size Replacement ($89, 3 variants)"
end

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  3. MENU LOCATIONS & ITEMS                                                ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seeding Menu Locations & Items ==="

menu_defs = {
  header_primary: {
    title: "Header Primary",
    location: "header_primary",
    items: [
      { name: "How to Use",  url: "/how-to-use",    position: 1 },
      { name: "Starter Kit", url: "/starter-kit",   position: 2 },
      { name: "Refills",     url: "/refills",        position: 3 },
      { name: "Learn More",  url: "/learn-more",     position: 4 },
      { name: "About",       url: "#",               position: 5,
        children: [
          { name: "About Cntrl+", url: "/about-cntrl", position: 1 },
          { name: "Videos",       url: "/videos",       position: 2 },
          { name: "Insights",     url: "/insights",     position: 3 },
          { name: "FAQ",          url: "/faq",           position: 4 },
        ]
      },
      { name: "News", url: "/news", position: 6 },
    ]
  },
  header_utilities: {
    title: "Header Utilities",
    location: "header_utilities",
    items: [
      { name: "Sign In", url: "/account/login", position: 1, item_class: "utility-link" },
      { name: "Cart",    url: "/cart",           position: 2, item_class: "utility-link" },
    ]
  },
  footer_support: {
    title: "Footer — Support",
    location: "footer_support",
    items: [
      { name: "FAQs",       url: "/faq",        position: 1 },
      { name: "How to Use", url: "/how-to-use", position: 2 },
      { name: "Contact",    url: "/contact",    position: 3 },
    ]
  },
  footer_company: {
    title: "Footer — Company",
    location: "footer_company",
    items: [
      { name: "About",      url: "/about-cntrl", position: 1 },
      { name: "Learn More", url: "/learn-more",  position: 2 },
      { name: "Insights",   url: "/insights",    position: 3 },
      { name: "Affiliates", url: "/affiliates",  position: 4 },
    ]
  },
  footer_policies: {
    title: "Footer — Policies",
    location: "footer_policies",
    items: [
      { name: "Replacement Policy", url: "/replacement-policy-and-limited-warranty", position: 1 },
      { name: "Terms of Service",   url: "/terms-of-service",                      position: 2 },
      { name: "Privacy Policy",     url: "/privacy-policy",                        position: 3 },
      { name: "Accessibility",      url: "/accessibility",                          position: 4 },
    ]
  },
}

menu_defs.each do |_key, defn|
  loc = MenuLocation.find_or_create_by!(location: defn[:location]) do |ml|
    ml.title      = defn[:title]
    ml.is_visible = true
  end
  puts "  Menu: #{loc.title}"

  defn[:items].each do |item_attrs|
    children = item_attrs.delete(:children)
    desired_pos = item_attrs[:position]

    item = MenuItem.find_or_create_by!(
      name: item_attrs[:name],
      menu_location_id: loc.id,
      parent_id: nil
    ) do |mi|
      mi.url         = item_attrs[:url]
      mi.item_class  = item_attrs[:item_class]
      mi.is_visible  = true
    end
    item.update_column(:position, desired_pos)
    puts "    #{item.name} (pos #{desired_pos})"

    next unless children
    children.each do |child_attrs|
      child_pos = child_attrs[:position]
      child = MenuItem.find_or_create_by!(
        name: child_attrs[:name],
        menu_location_id: loc.id,
        parent_id: item.id
      ) do |mi|
        mi.url        = child_attrs[:url]
        mi.is_visible = true
      end
      child.update_column(:position, child_pos)
      puts "      └ #{child.name} (pos #{child_pos})"
    end
  end
end

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  4. HOMEPAGE SECTIONS                                                     ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seeding Homepage Sections ==="

homepage_sections = [
  {
    title: "Announcement Bar",
    section_type: "custom",
    content: "Now available in the U.S. — Free Shipping on Your First Order",
    position: 1,
    is_visible: true,
    settings: {
      style: "announcement",
      background_color: "#0B3B3C",
      text_color: "#ffffff",
      link: "/products/starter-kit"
    }
  },
  {
    title: "Hero",
    section_type: "hero",
    content: "<h1>Move without planning around leaks.</h1><p>Discreet leak support for active women. Worn like a tampon, Cntrl+ helps prevent leaks during movement so you can run, jump, laugh, and live.</p>",
    position: 2,
    is_visible: true,
    settings: {
      background_image_desktop: "https://cntrlplus.com/cdn/shop/files/Banner-Home-Desktop.webp",
      background_image_mobile: "https://cntrlplus.com/cdn/shop/files/Banner-Home-Mobile-2.webp",
      cta_primary_text: "LEARN MORE",
      cta_primary_link: "/pages/learn-more",
      cta_secondary_text: "GET STARTED",
      cta_secondary_link: "/products/starter-kit",
      text_color: "#ffffff",
      overlay_opacity: 0.3
    }
  },
  {
    title: "How It Works",
    section_type: "content",
    content: "<h2>How Cntrl+ works</h2><p>Cntrl+ is worn internally, similar to a tampon or menstrual cup. Once in place, it provides gentle support that helps prevent leaks during movement. It's designed to be comfortable, discreet, and easy to use.</p>",
    position: 3,
    is_visible: true,
    settings: {
      layout: "steps",
      steps: [
        { number: 1, text: "Bladder leaks often happen during movement: running, jumping, laughing, lifting. Cntrl+ is designed to help prevent those leaks before they happen.", image: "https://cntrlplus.com/cdn/shop/files/Step_1-Cntrl.jpg" },
        { number: 2, text: "Cntrl+ is worn internally, similar to a tampon or menstrual cup. It's soft, flexible, and designed to sit comfortably in place during activity.", image: "https://cntrlplus.com/cdn/shop/files/Step_2-Cntrl.jpg" },
        { number: 3, text: "Once in place, Cntrl+ provides gentle support that helps reduce leaks during movement. Most women say they don't feel it once it's in.", image: "https://cntrlplus.com/cdn/shop/files/Step_3-Cntrl.jpg" },
        { number: 4, text: "To remove, simply pull the string like you would a tampon, or gently hook a finger around the band and slide it out, similar to a menstrual cup.", image: "https://cntrlplus.com/cdn/shop/files/Step_4-Cntrl.jpg" }
      ]
    }
  },
  {
    title: "Why Cntrl+",
    section_type: "content",
    content: "<h2>Take back your day.</h2><p>Putting on a bra for support is just part of getting dressed. Cntrl+ is similar — discreet support designed to move with you. Wear it for up to 12 hours during the moments when leaks are most likely to happen.</p>",
    position: 4,
    is_visible: true,
    settings: {
      layout: "two_column",
      image: "https://cntrlplus.com/cdn/shop/files/Process-6734.webp",
      image_position: "right",
      cta_text: "START YOUR ONLINE PRESCRIPTION",
      cta_link: "/products/starter-kit"
    }
  },
  {
    title: "Not a Pad, Not Surgery",
    section_type: "content",
    content: "<h2>A better way</h2><ul><li>It's not a pad</li><li>It's not surgery</li><li>It's not visible</li><li>It's not complicated</li></ul>",
    position: 5,
    is_visible: true,
    settings: {
      layout: "feature_list",
      style: "minimal"
    }
  },
  {
    title: "Features — What Women Are Saying",
    section_type: "features",
    content: "<h2>What women are saying</h2><p>In a small study of women using Cntrl+ at home for two weeks:</p>",
    position: 6,
    is_visible: true,
    settings: {
      features: [
        { icon: "https://cntrlplus.com/cdn/shop/files/Icon-90.png", title: "90%", description: "Experienced fewer or no leaks after two weeks." },
        { icon: "https://cntrlplus.com/cdn/shop/files/Icon-70.png", title: "70%", description: "Reported it was comfortable to wear." },
        { icon: "https://cntrlplus.com/cdn/shop/files/Icon-95.png", title: "95%", description: "Said it was easy to care for at home." }
      ]
    }
  },
  {
    title: "CTA — Ready to Move",
    section_type: "call_to_action",
    content: "<h2>Ready to move without planning around leaks?</h2>",
    position: 7,
    is_visible: true,
    settings: {
      background_image: "https://cntrlplus.com/cdn/shop/files/Process-7818_B.webp",
      button_text: "START YOUR ONLINE PRESCRIPTION",
      button_link: "/products/starter-kit",
      text_color: "#ffffff"
    }
  },
  {
    title: "Newsletter Signup",
    section_type: "newsletter",
    content: "<h2>Join the 1000's of active women ready to take back control.</h2><p>Sign up to receive important updates and information about where you can get your Cntrl+.</p>",
    position: 8,
    is_visible: true,
    settings: {
      background_color: "#f8f9fa",
      button_text: "Subscribe",
      privacy_text: "We respect your privacy."
    }
  },
  {
    title: "Instagram Grid",
    section_type: "gallery",
    content: "<h2>Follow Us on Instagram</h2>",
    position: 9,
    is_visible: true,
    settings: {
      columns: 4,
      spacing: 10,
      instagram_handle: "@cntrlplus",
      enable_lightbox: true,
      images: []
    }
  }
]

homepage_sections.each do |attrs|
  desired_position = attrs[:position]
  hs = HomepageSection.find_or_initialize_by(title: attrs[:title])
  if hs.new_record?
    hs.assign_attributes(attrs.except(:position))
    hs.position = desired_position  # set before validation
    hs.save!
    hs.update_column(:position, desired_position)
  else
    hs.update!(attrs.except(:position))
    hs.update_column(:position, desired_position)
  end
  puts "  [#{desired_position}] #{attrs[:title]} (#{attrs[:section_type]})"
end

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  5. PAGES                                                                 ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seeding Pages ==="

# Helper to create a page idempotently
def seed_page(attrs)
  page = Spree::Page.find_or_initialize_by(slug: attrs[:slug])
  page.assign_attributes(attrs)
  page.save!
  puts "  [#{attrs[:layout]}] #{attrs[:slug]}"
  page
end

# -------------------------------------------------------------------------
# 5a. CMS Pages (layout: "cms", body = JSON array of sections)
# -------------------------------------------------------------------------
puts "  --- CMS Pages ---"

seed_page(
  title: "Learn More",
  slug: "learn-more",
  layout: "cms",
  visible: true,
  position: 1,
  meta_title: "Learn More About Cntrl+ Bladder Support",
  meta_description: "Cntrl+ is a discreet, wearable support designed to help prevent bladder leaks during activity.",
  body: [
    { type: "hero-banner", content: {
      heading: "Bladder leaks happen. Especially when you move.",
      subheading: "Cntrl+ is a discreet, wearable support designed to help prevent leaks during activity.",
      cta_text: "Start Your Online Prescription",
      cta_link: "/products/starter-kit",
      backgroundImage: "https://cntrlplus.com/cdn/shop/files/Banner-LearnMore-2.webp"
    }},
    { type: "text-image-split", content: {
      heading: "You're not the only one.",
      body: "Millions of active women experience leaks when they run, jump, laugh, or sneeze. It's common. It's frustrating. And it's not something you just have to 'live with.'",
      image: "https://cntrlplus.com/cdn/shop/files/C1W-08087.webp"
    }},
    { type: "step-carousel", content: {
      heading: "How Cntrl+ works",
      intro: "Cntrl+ is worn internally, similar to a tampon or menstrual cup. Once in place, it provides gentle support that helps prevent leaks during movement.",
      steps: [
        { number: 1, text: "Bladder leaks often happen during movement: running, jumping, laughing, lifting. Cntrl+ is designed to help prevent those leaks before they happen.", image: "https://cntrlplus.com/cdn/shop/files/Step_1-Cntrl.jpg" },
        { number: 2, text: "Cntrl+ is worn internally, similar to a tampon or menstrual cup. It's soft, flexible, and designed to sit comfortably in place during activity.", image: "https://cntrlplus.com/cdn/shop/files/Step_2-Cntrl.jpg" },
        { number: 3, text: "Once in place, Cntrl+ provides gentle support that helps reduce leaks during movement. Most women say they don't feel it once it's in.", image: "https://cntrlplus.com/cdn/shop/files/Step_3-Cntrl.jpg" },
        { number: 4, text: "To remove, simply pull the string like you would a tampon, or gently hook a finger around the band and slide it out, similar to a menstrual cup.", image: "https://cntrlplus.com/cdn/shop/files/Step_4-Cntrl.jpg" }
      ]
    }},
    { type: "feature-list", content: {
      items: ["It's not a pad", "It's not surgery", "It's not visible", "It's not complicated"]
    }},
    { type: "stats-row", content: {
      heading: "What women are saying",
      intro: "In a small study of women using Cntrl+ at home for two weeks:",
      stats: [
        { value: "90%", label: "Experienced fewer or no leaks after two weeks.", icon: "https://cntrlplus.com/cdn/shop/files/Icon-90.png" },
        { value: "70%", label: "Reported it was comfortable to wear.", icon: "https://cntrlplus.com/cdn/shop/files/Icon-70.png" },
        { value: "95%", label: "Said it was easy to care for at home.", icon: "https://cntrlplus.com/cdn/shop/files/Icon-95.png" }
      ]
    }},
    { type: "comparison-chart", content: {
      heading: "Why not just use pads?",
      left_label: "Pads absorb leaks",
      right_label: "Cntrl+ helps prevent them",
      chart_image: "https://cntrlplus.com/cdn/shop/files/Chart_4e412283-4704-4852-8496-3e58bb5ba78f.png"
    }},
    { type: "hero-banner", content: {
      heading: "Ready to move without planning around leaks?",
      cta_text: "START YOUR ONLINE PRESCRIPTION",
      cta_link: "/products/starter-kit",
      backgroundImage: "https://cntrlplus.com/cdn/shop/files/Process-7818_B.webp"
    }}
  ].to_json
)

seed_page(
  title: "How to Use",
  slug: "cntrlplus-how-to-use",
  layout: "cms",
  visible: true,
  position: 2,
  meta_title: "How to Use Cntrl+ Bladder Support",
  meta_description: "Step-by-step guide to inserting, wearing, removing, and cleaning your Cntrl+ bladder support device.",
  body: [
    { type: "hero-banner", content: {
      heading: "How to use",
      subheading: "We designed Cntrl+ for women like you — women who want to feel confident again and get back to living life freely, without leaks calling the shots."
    }},
    { type: "step-carousel", content: {
      heading: "Insertion Guide",
      steps: [
        { number: 1, title: "Prep", text: "Empty bladder. Wash hands with mild soap and warm water. Clean Cntrl+ before use." },
        { number: 2, title: "Add Removal String (optional)", text: "Thread through outer straight-side hole. Pass through outer hole on circular ring top. Pull taut and secure. Use new string each time." },
        { number: 3, title: "Position Your Body", text: "Take three deep breaths. Relax pelvic muscles. Choose comfortable position: toilet, squat, or lying down." },
        { number: 4, title: "Fold & Lubricate", text: "Squeeze circular band between thumb and index finger. Wet with warm water or use dime-sized water-based lubricant." },
        { number: 5, title: "Insert", text: "Separate labia with fingers. Insert upward-back at 45-degree angle toward tailbone. Keep long flat side facing back of vagina." }
      ]
    }},
    { type: "text-image-split", content: {
      heading: "Removal",
      body: "Wash hands for 30 seconds. Assume comfortable position. Take three deep breaths and relax pelvic floor. With string: gently pull downward. Without string: insert index finger, hook around circular band top, slowly pull forward and out."
    }},
    { type: "faq-accordion", content: {
      heading: "Sizing & Troubleshooting",
      items: [
        { q: "Having trouble inserting?", a: "Take deep breaths, relax pelvic floor. Add small amount of water-based lubricant to leading edge for easier gliding." },
        { q: "Cntrl+ slipping out?", a: "Remove before bowel movements; reinsert after. May need larger size. Contact healthcare provider if persistent." },
        { q: "Uncomfortable or can't empty bladder?", a: "Push further with index finger or try smaller size. Never power through pain. Contact support or healthcare provider." },
        { q: "How long can I wear it?", a: "Up to 12 hours per 24-hour period maximum. Nightly removal recommended." }
      ]
    }},
    { type: "text-block", content: {
      heading: "Contact Support",
      body: "If you need help, contact us at support@cntrlplus.com or call 1 (833) 784-5190, Monday–Friday 8am–8pm continental US."
    }},
    { type: "hero-banner", content: {
      heading: "Ready to get started?",
      cta_text: "GET YOUR STARTER KIT",
      cta_link: "/products/starter-kit"
    }}
  ].to_json
)

seed_page(
  title: "FAQ",
  slug: "faq",
  layout: "cms",
  visible: true,
  position: 3,
  meta_title: "Frequently Asked Questions — Cntrl+",
  meta_description: "Find answers to common questions about Cntrl+ bladder support — what it is, how it works, sizing, cost, and safety.",
  body: [
    { type: "hero-banner", content: {
      heading: "Frequently Asked Questions",
      subheading: "Everything you need to know about Cntrl+."
    }},
    { type: "faq-accordion", content: {
      heading: "What Is Cntrl+",
      items: [
        { q: "What is Cntrl+?", a: "Cntrl+ is a reusable bladder support worn inside the body, designed to stop leaks during everyday activities. It functions internally to prevent leaks during movement, exercise, coughing, sneezing, and laughing." },
        { q: "Does it stay in place during activity?", a: "Yes. A two-week home-use study with 20 participants showed the device remained stable throughout various activities and the full wear period." },
        { q: "Can I use it if I've never used a device like this before?", a: "Absolutely. The product is designed for self-fitting and home management. Most study participants had no prior experience with similar devices and successfully used it." }
      ]
    }},
    { type: "faq-accordion", content: {
      heading: "How It Works",
      items: [
        { q: "Where does it go, and how does it work?", a: "The device sits comfortably inside the vagina, where it gently holds everything in place during moments of abdominal pressure from laughing, running, sneezing, or jumping." },
        { q: "Is it hard plastic or flexible? What is it made of?", a: "Cntrl+ is made from Santoprene, a soft, flexible medical-grade material used in respiratory masks and IV components. It's tested to international safety standards." },
        { q: "How do I choose the right size?", a: "The Starter Kit includes all three sizes with 90 cotton removal strings. Start with the smallest size and advance until achieving comfort and effectiveness." },
        { q: "How long does one device last?", a: "Each device is reusable for up to 90 uses, roughly three months of regular use. Replace when it no longer stops leaks and a deep crease appears at the ring's top." },
        { q: "Can I wear it at night?", a: "No. Cntrl+ is designed for daytime use, when leaks tend to happen most — during movement, exercise, and similar activities. Not for overnight wear." },
        { q: "Does it work for everyday leaks, not just exercise?", a: "Yes. It addresses leaks triggered by walking, lifting, laughing, sneezing, picking something up, or just moving through your day." },
        { q: "Does using it improve my condition over time?", a: "No. Cntrl+ manages leaks while you wear it but isn't designed to produce long-term pelvic floor changes. It works alongside other treatments." }
      ]
    }},
    { type: "faq-accordion", content: {
      heading: "Getting Started",
      items: [
        { q: "Do I need to see my own doctor?", a: "No. You complete a short online health intake, a licensed provider reviews your responses, and issues a prescription entirely online without appointments." },
        { q: "What exactly is the online consultation?", a: "No video call required. You complete a short written health intake and a licensed provider reviews it. If approved, your prescription and order process begins." },
        { q: "How quickly does the provider respond?", a: "Most reviews are completed within a few hours of submission. Orders ship immediately after approval." },
        { q: "What if it doesn't fit?", a: "The three-size Starter Kit allows at-home fitting without assistance. Customer support is available for additional help." }
      ]
    }},
    { type: "faq-accordion", content: {
      heading: "Cost & Insurance",
      items: [
        { q: "Does the $159 include everything?", a: "Yes. The price covers the complete Cntrl+ Starter Kit: the device in all three sizes, 90 cotton removal strings, an organic cotton travel bag, the licensed provider review, and 12 months of telehealth access. No hidden fees." },
        { q: "Is it a one-time purchase or a subscription?", a: "The first purchase is the Starter Kit at $159. Afterward, you choose when to order your Single Size Replacement. No mandatory subscription, no automatic charges." },
        { q: "What is the refill?", a: "Devices are reusable for up to 90 uses, about three months of regular use. Single Size Replacements provide fresh devices when the original needs replacing." },
        { q: "Is it covered by HSA or FSA?", a: "Yes. Cntrl+ is FSA and HSA eligible, which means you can use pre-tax healthcare funds to purchase it. A Letter of Medical Necessity is provided post-approval." }
      ]
    }},
    { type: "faq-accordion", content: {
      heading: "Safety",
      items: [
        { q: "Is Cntrl+ right for me?", a: "Cntrl+ addresses stress urinary incontinence — the kind of bladder leak triggered by movement, pressure, laughing, sneezing, coughing, or exercise. It's unsuitable for those with active UTIs, significant prolapse, vaginal atrophy, cystitis, vaginal soreness, abnormal bleeding/discharge, or IUDs." },
        { q: "Is it safe? What clinical testing has been done?", a: "Cntrl+ underwent a rigorous FDA clearance process reviewing safety testing, materials, and performance. In a home-use study, nearly 9 in 10 participants reported that Cntrl+ stopped or significantly reduced their bladder leaks. Zero adverse events occurred." },
        { q: "Can I use it if I'm postpartum?", a: "Cntrl+ is generally not recommended until after the standard 12-week or 3-month postpartum recovery period. The prescribing clinician confirms timing suitability." }
      ]
    }}
  ].to_json
)

seed_page(
  title: "About Cntrl+",
  slug: "about-cntrl",
  layout: "cms",
  visible: true,
  position: 4,
  meta_title: "About Cntrl+ — Our Mission & Team",
  meta_description: "At Cntrl+ our goal is to help women of all ages regain their comfort and confidence by conveniently helping them manage bladder leaks.",
  body: [
    { type: "hero-banner", content: {
      heading: "About Cntrl+",
      subheading: "At Cntrl+ our goal is to help women of all ages regain their comfort and confidence by conveniently helping them to manage bladder leaks, overactive bladder, forms of pelvic organ prolapse like rectocele and pelvic pain — to live, life, freely!"
    }},
    { type: "text-image-split", content: {
      heading: "Our Founder",
      body: "Karen Brunet, CEO/Founder, drew on personal medical challenges including PCOS and stage 4 endometriosis to launch a medical supply company (ActivKare, acquired 2024) and developed the Cntrl+ bladder support device to address stress urinary incontinence while supporting pelvic floor health during exercise.",
      image: "https://cntrlplus.com/cdn/shop/files/Karen_Brunet.png"
    }},
    { type: "team-cards", content: {
      heading: "Our Team",
      members: [
        { name: "Karen Brunet", title: "CEO/Founder", location: "Cornwall, ON", bio: "25+ years CPG sales leadership" },
        { name: "Marco Cignini", title: "Chief Brand Officer/Co-founder", location: "New York, NY", bio: "Global marketing & branding expert" },
        { name: "Morgan Donaldson", title: "Fractional CCO", location: "Ottawa, ON", bio: "Former VP Sales @ Fullscript; 20+ years health tech" },
        { name: "Russ Patterson", title: "COO/CFO", location: "Mississauga, ON", bio: "Former eBay Canada GM, 3-time CEO" },
        { name: "Lisa Curran", title: "CMO", location: "San Francisco, CA", bio: "Healthcare/medical device marketing leader; 10+ global product launches" },
        { name: "Dr. Charusheila Ramkumar", title: "Regulatory & R&D", location: "Toronto", bio: "MD, PhD Biomedical Sciences, RAC credential" },
        { name: "Camellia Khanjan Nezhad", title: "Quality Manager", location: "Toronto", bio: "MSc., CQA designation; cGMP/ISO standards expertise" },
        { name: "Madeleine Tobias", title: "Business Admin Manager", location: "Kingston, ON", bio: "10+ years business operations" }
      ]
    }},
    { type: "advisor-cards", content: {
      heading: "Medical Advisors",
      advisors: [
        { name: "Dr. Mary Polan", title: "Obstetrician & Gynecologist, Professor at Yale University" },
        { name: "Dr. Bertha Chen", title: "Urogynecologist, Professor at Stanford University" },
        { name: "Dr. Aisling Clancy", title: "Urogynecologist, Ottawa Civic Hospital & Adjunct Professor at University of Ottawa" },
        { name: "Dr. Linda McLean", title: "Research Advisor, Professor at University of Ottawa & Queens University" }
      ]
    }},
    { type: "logo-grid", content: {
      heading: "Affiliations & Partners",
      logos: ["Yale University", "Stanford Children's Hospital", "Queen's University", "University of Ottawa", "Launch Lab", "ACC Futures", "OC Innovation", "iF Design", "Springboard", "Avania Clinical"],
      image: "https://cntrlplus.com/cdn/shop/files/FOOTER_LOGOS_1.png"
    }},
    { type: "hero-banner", content: {
      heading: "Ready to take control?",
      cta_text: "GET STARTED",
      cta_link: "/products/starter-kit"
    }}
  ].to_json
)

seed_page(
  title: "News",
  slug: "news",
  layout: "cms",
  visible: true,
  position: 5,
  meta_title: "News & Press — Cntrl+",
  meta_description: "Press coverage and releases about Cntrl+ bladder support.",
  body: [
    { type: "hero-banner", content: {
      heading: "News",
      subheading: "Articles & Press"
    }},
    { type: "press-cards", content: {
      heading: "Articles",
      articles: [
        { title: "Empowering Women Worldwide With Cntrl+", source: "Ontario Centre of Innovation", url: "https://oc-innovation.ca/success-stories/empowering-women-worldwide-with-cntrl/" },
        { title: "FDA Clears Cntrl+: A Revolutionary Bladder Leak Support Product for Women", source: "Femtech Canada", url: "https://femtech.ca/fda-clears-cntrl-a-revolutionary-bladder-leak-support-product-for-women/" },
        { title: "Women's Health Startup Cntrl+ Launches FDA-Cleared Bladder Support Device", source: "The Columbus Dispatch", url: "https://dispatch.com/press-release/story/142961/womens-health-startup-cntrl-launches-fda-cleared-bladder-support-device/" },
        { title: "Cntrl+ Inc. receives clearance from the US Food and Drug Administration", source: "Queen's University", url: "https://queensu.ca/partnershipsandinnovation/news/cntrl-receives-us-fda-clearance" }
      ]
    }},
    { type: "text-block", content: {
      heading: "Press Releases",
      body: "<p><strong>January 2025</strong> — FDA Clears Cntrl+: A Revolutionary Bladder Leak Support Product for Women</p><p><strong>November 2024</strong> — Cntrl+ Secures $500,000 Investment from Ontario Centre for Innovation to Revolutionize Female Bladder Support Market</p>"
    }}
  ].to_json
)

seed_page(
  title: "Videos",
  slug: "videos",
  layout: "cms",
  visible: true,
  position: 6,
  meta_title: "Videos — Cntrl+",
  meta_description: "Watch videos about Cntrl+ bladder support.",
  body: [
    { type: "hero-banner", content: {
      heading: "Videos",
      subheading: "Learn more about Cntrl+ through our video library."
    }},
    { type: "video-gallery", content: {
      heading: "Video Gallery",
      placeholder: true,
      videos: []
    }}
  ].to_json
)

seed_page(
  title: "Healthcare Professionals",
  slug: "healthcare-professionals",
  layout: "cms",
  visible: true,
  position: 7,
  meta_title: "For Healthcare Professionals — Cntrl+",
  meta_description: "A prescription-ready bladder support your patients can actually self-manage. FDA-cleared, reusable, non-surgical.",
  body: [
    { type: "hero-banner", content: {
      heading: "A prescription-ready bladder support your patients can actually self-manage.",
      subheading: "Cntrl+ is an FDA-cleared, reusable device for stress urinary incontinence. Non-surgical, non-hormonal, no in-office fitting required.",
      cta_text: "Try a Starter Kit",
      cta_link: "/products/starter-kit"
    }},
    { type: "stats-row", content: {
      heading: "Clinical Study Results",
      intro: "McLean Usability and Effectiveness Study, University of Ottawa (November 2025), n=20, 2-week home-use",
      stats: [
        { value: "89%", label: "reported reduced or eliminated bladder leaks (16 of 18 participants)" },
        { value: "85%", label: "maintained normal voiding while wearing device (17 of 20 participants)" },
        { value: "95%", label: "reported ease of care over two weeks (19 of 20 participants)" }
      ]
    }},
    { type: "text-block", content: {
      heading: "FDA & Regulatory Details",
      body: "<ul><li>FDA cleared (510(k) K240798)</li><li>Classification: Prescription device</li><li>Diagnosis Code: N39.3</li><li>EHR Integration: Available via Honeybee Health</li><li>Safety Record: Zero adverse events reported</li></ul>"
    }},
    { type: "step-carousel", content: {
      heading: "Prescribing Pathway",
      steps: [
        { number: 1, text: "Patient completes brief online health intake at cntrlplus.com (no appointment needed)" },
        { number: 2, text: "Licensed prescriber reviews and approves within 4 hours via asynchronous clinical review" },
        { number: 3, text: "Starter Kit ships directly to patient; one prescription covers kit plus 11 refills" }
      ]
    }},
    { type: "text-block", content: {
      heading: "EHR & Insurance",
      body: "<p>EHR prescribing through Honeybee Health coming soon. FSA/HSA eligible with Letter of Medical Necessity. Starter Kit: $159. Replace every 90 days. No referral paperwork or follow-up billing required.</p>"
    }},
    { type: "hero-banner", content: {
      heading: "Partner with Cntrl+",
      subheading: "Email partnerships@cntrlplus.com or call 1 (833) 784-5190.",
      cta_text: "CONTACT US",
      cta_link: "/pages/contact"
    }}
  ].to_json
)

# -------------------------------------------------------------------------
# 5b. Landing Pages (layout: "landing", body = JSON hero overrides)
# -------------------------------------------------------------------------
puts "  --- Landing Pages ---"

seed_page(
  title: "Move Freely",
  slug: "move-freely",
  layout: "landing",
  visible: true,
  position: 8,
  meta_title: "Move Freely — Cntrl+",
  meta_description: "Don't let leaks bench you. Cntrl+ is discreet leak support for active women.",
  body: {
    hero_headline: "Don't let leaks bench you.",
    hero_subheading: "We designed Cntrl+ for women like you — women who want to feel confident again and get back to living life freely, without leaks calling the shots.",
    target_audience: "Active women experiencing bladder leaks during movement, exercise, laughing, sneezing, coughing, or daily activities.",
    cta_text: "See if I'm a candidate",
    cta_link: "/products/starter-kit"
  }.to_json
)

seed_page(
  title: "New Chapter",
  slug: "new-chapter",
  layout: "landing",
  visible: true,
  position: 9,
  meta_title: "New Chapter — Cntrl+",
  meta_description: "You made a human. Your body deserves real support.",
  body: {
    hero_headline: "You made a human. Your body deserves real support.",
    hero_subheading: "Postpartum leaks are common and don't require acceptance — Cntrl+ provides designed support for this reality.",
    target_audience: "Postpartum individuals experiencing bladder leaks, seeking alternatives to pads or adult briefs.",
    cta_text: "Start your 2-minute assessment",
    cta_link: "/products/starter-kit"
  }.to_json
)

seed_page(
  title: "Life in Motion",
  slug: "life-in-motion",
  layout: "landing",
  visible: true,
  position: 10,
  meta_title: "Life in Motion — Cntrl+",
  meta_description: "Your body is changing. Control doesn't have to.",
  body: {
    hero_headline: "Your body is changing. Control doesn't have to.",
    hero_subheading: "Nobody puts bladder leaks on the perimenopause brochure. But here you are, and here we are. Cntrl+ is the non-surgical, non-hormonal solution designed for exactly this chapter.",
    target_audience: "Women experiencing perimenopause and stress urinary incontinence, seeking non-surgical, non-hormonal solutions.",
    cta_text: "Start your 2-minute assessment",
    cta_link: "/products/starter-kit"
  }.to_json
)

seed_page(
  title: "Your Impressa Alternative",
  slug: "your-impressa-alternative",
  layout: "landing",
  visible: true,
  position: 11,
  meta_title: "Your Impressa Alternative — Cntrl+",
  meta_description: "Impressa is gone. Here's what's next. Cntrl+ is FDA-cleared, reusable up to 90 times.",
  body: {
    hero_headline: "Impressa is gone. Here's what's next.",
    hero_subheading: "They discontinued it like a limited edition snack. We get it. Cntrl+ is FDA-cleared, reusable up to 90 times, and ready to ship to your door. Your routine isn't over. It just has a new name.",
    target_audience: "Women who previously used Impressa for bladder leak support, seeking a replacement product.",
    cta_text: "Get your starter kit",
    cta_link: "/products/starter-kit"
  }.to_json
)

# -------------------------------------------------------------------------
# 5c. Simple Pages (layout: "simple", body = HTML string)
# -------------------------------------------------------------------------
puts "  --- Simple Pages ---"

seed_page(
  title: "Contact",
  slug: "contact",
  layout: "simple",
  visible: true,
  position: 12,
  meta_title: "Contact Us — Cntrl+",
  meta_description: "Get in touch with the Cntrl+ team for support, questions, or feedback.",
  body: <<~HTML
    <h1>Contact Us</h1>
    <p>We're here to help. Reach out to the Cntrl+ team for support, questions, or feedback.</p>
    <h2>Customer Support</h2>
    <p><strong>Phone:</strong> 1 (833) 784-5190</p>
    <p><strong>Email:</strong> <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a></p>
    <p><strong>Hours:</strong> Monday – Friday, 8am – 8pm (Continental US)</p>
    <h2>Mailing Address</h2>
    <p>Cntrl+ Inc.<br>127 Augustus Street, Unit 1<br>Cornwall, Ontario, K6J 3V9, Canada</p>
  HTML
)

seed_page(
  title: "Accessibility",
  slug: "accessibility",
  layout: "simple",
  visible: true,
  position: 13,
  meta_title: "Accessibility — Cntrl+",
  meta_description: "Cntrl+ is committed to providing an inclusive shopping experience for all users.",
  body: <<~HTML
    <h1>Accessibility</h1>
    <p>Cntrl+ is committed to providing an inclusive shopping experience and continuously improving website accessibility for all users, including individuals with disabilities.</p>
    <h2>Accessibility Assistance</h2>
    <p>If you encounter navigation or purchase challenges, please contact our support team at <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a>. We will provide information through accessible communication methods in accordance with applicable laws.</p>
    <h2>Feedback</h2>
    <p>We value your input on accessibility improvements. Please submit suggestions or report barriers by emailing <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a>.</p>
  HTML
)

seed_page(
  title: "Data Sharing Opt-Out",
  slug: "data-sharing-opt-out",
  layout: "simple",
  visible: true,
  position: 14,
  meta_title: "Your Privacy Choices — Cntrl+",
  meta_description: "Manage your data sharing preferences with Cntrl+.",
  body: <<~HTML
    <h1>Your Privacy Choices</h1>
    <p>We collect personal information from your interactions with us and our website, including through cookies and similar technologies.</p>
    <h2>Data Sharing Disclosure</h2>
    <p>Personal information may be shared with third parties, particularly advertising partners, to deliver more relevant ads across different websites.</p>
    <h2>Your Rights</h2>
    <p>Depending on your location, you may have rights to opt out of activities that qualify as "sales," "sharing," or "targeted advertising" under state privacy laws.</p>
    <h2>Global Privacy Control</h2>
    <p>We acknowledge the Global Privacy Control opt-out preference signal. When enabled, Cntrl+ will honor requests to limit data use for advertising purposes on the device and browser used.</p>
  HTML
)

seed_page(
  title: "Replacement Policy and Limited Warranty",
  slug: "replacement-policy-and-limited-warranty",
  layout: "simple",
  visible: true,
  position: 15,
  meta_title: "Replacement Policy & Limited Warranty — Cntrl+",
  meta_description: "Cntrl+ offers a 30-day limited warranty covering manufacturing defects.",
  body: <<~HTML
    <h1>Replacement Policy and Limited Warranty</h1>
    <h2>Overview</h2>
    <p>Cntrl+ offers a 30-day limited warranty covering manufacturing defects for products purchased directly from authorized sellers. Claims must be submitted within 15 days of receipt.</p>
    <h2>Coverage</h2>
    <p>The warranty applies exclusively to products purchased directly from Cntrl+ or an authorized Cntrl+ seller. Purchases from unauthorized sources may result in rejected claims, except where law prohibits such restrictions.</p>
    <h2>What's Excluded</h2>
    <p>The policy does not cover normal wear and tear, discoloration from regular use, damage from misuse, improper care, neglect, or unauthorized modifications.</p>
    <h2>Claims Process</h2>
    <p>Contact support at <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a> with:</p>
    <ul>
      <li>A clear photo showing the defect</li>
      <li>Proof of purchase (receipt or order confirmation)</li>
      <li>Images of the product label if seal tampering is suspected</li>
    </ul>
    <h2>Resolution</h2>
    <p>Upon approval, Cntrl+ will either replace the defective product or refund the original purchase price, at the company's discretion. Prepaid return shipping is provided if inspection is needed.</p>
  HTML
)

seed_page(
  title: "Terms of Service",
  slug: "terms-of-service",
  layout: "simple",
  visible: true,
  position: 16,
  meta_title: "Terms of Service — Cntrl+",
  meta_description: "Terms and conditions governing use of the Cntrl+ website and services.",
  body: <<~HTML
    <h1>Terms of Service</h1>
    <p>This website is operated by Cntrl Plus. By visiting or purchasing from the site, you agree to be bound by the following terms, conditions, and policies.</p>
    <h2>Online Store Terms</h2>
    <p>By agreeing to these Terms of Service, you represent that you are at least the age of majority in your state or province of residence. You may not use our products for any illegal or unauthorized purpose. Any breach of these terms results in immediate service termination.</p>
    <h2>General Conditions</h2>
    <p>We reserve the right to refuse service to anyone for any reason at any time. Content may be transferred unencrypted across networks; credit card information is always encrypted. You may not reproduce or exploit any portion of the service without written permission.</p>
    <h2>Accuracy of Information</h2>
    <p>We are not responsible if information made available on this site is not accurate, complete, or current. Material is provided for general information only and should not be relied upon as the sole basis for making decisions.</p>
    <h2>Products and Pricing</h2>
    <p>We reserve the right to modify prices and discontinue products or services without notice. Product colors and images are displayed as accurately as possible, but monitor display accuracy cannot be guaranteed.</p>
    <p>For the full terms, please contact <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a>.</p>
  HTML
)

seed_page(
  title: "Privacy Policy",
  slug: "privacy-policy",
  layout: "simple",
  visible: true,
  position: 17,
  meta_title: "Privacy Policy — Cntrl+",
  meta_description: "How Cntrl+ collects, uses, and discloses your personal information.",
  body: <<~HTML
    <h1>Privacy Policy</h1>
    <p>Cntrl+ operates this store and website to provide customers with a curated shopping experience powered by Shopify. This policy describes how personal information is collected, used, and disclosed when you visit, use, or make purchases through our Services.</p>
    <h2>Information We Collect</h2>
    <p>We collect several categories of personal information depending on your interactions, including: contact details (name, address, phone, email), financial information (payment card details), account information, transaction details, device information (IP addresses), and usage data.</p>
    <h2>How We Use Your Information</h2>
    <p>We use personal information to provide and improve the Services, process payments, fulfill orders, remember preferences, create customized shopping experiences, send marketing communications, support security, detect fraud, and provide customer support.</p>
    <h2>Disclosure</h2>
    <p>We disclose personal information to Shopify, vendors, service providers, business and marketing partners, corporate affiliates, and as required by law. We do not sell personal information of individuals under 16.</p>
    <h2>SMS Program</h2>
    <p>Cntrl+ does not sell, rent, or share personal information collected through the SMS program with third parties for their own marketing or promotional purposes.</p>
    <p>For the full privacy policy, please contact <a href="mailto:support@cntrlplus.com">support@cntrlplus.com</a>.</p>
  HTML
)

seed_page(
  title: "Affiliates",
  slug: "affiliates",
  layout: "simple",
  visible: true,
  position: 18,
  meta_title: "Affiliate Program — Cntrl+",
  meta_description: "Join the Cntrl+ affiliate program and earn commissions promoting bladder support for active women.",
  body: <<~HTML
    <h1>Affiliate Program</h1>
    <p>Ready to join the Cntrl+ community? Drive traffic from your site or social channels to cntrlplus.com and turn it into real earnings.</p>
    <h2>How It Works</h2>
    <ol>
      <li>Apply through AvantLink affiliate network</li>
      <li>Complete application for Cntrl+ program</li>
      <li>Add custom Cntrl+ link to your content once approved</li>
      <li>Share with your audience and earn on purchases</li>
      <li>Track metrics via AvantLink dashboard</li>
    </ol>
    <h2>Commission Structure</h2>
    <ul>
      <li>Standard commissions: 10% on all sales</li>
      <li>Loyalty/deal sites: 5–2% respectively</li>
      <li>60-day cookie window for conversions</li>
    </ul>
    <h2>Who We're Looking For</h2>
    <p>Women's health & wellness creators, running and fitness communities, mom networks, pelvic health educators, product reviewers, and social creators.</p>
  HTML
)

seed_page(
  title: "Refills",
  slug: "refills",
  layout: "simple",
  visible: true,
  position: 19,
  meta_title: "Refills — Cntrl+",
  meta_description: "Order your Cntrl+ Single Size Replacement. Your device is reusable — until it isn't.",
  body: <<~HTML
    <h1>Refills</h1>
    <p>Your Cntrl+ is reusable. Until it isn't. Each device is designed for approximately 90 uses — roughly three months of regular use.</p>
    <h2>How to Reorder</h2>
    <p>Get a fresh device in the size that already works for your body for $89, shipped with zero starting over. A subscription option is coming soon.</p>
    <h2>When to Replace</h2>
    <p>When it stops doing its job or develops a deep crease at the top of the ring, it's earned its retirement.</p>
    <h2>Your Prescription</h2>
    <p>Prescription refills are included with the Starter Kit. Sign into your account to verify remaining refills. If your refills are exhausted, a quick new clinical review is required.</p>
    <p><a href="/products/single-size-replacement">Order your Single Size Replacement</a></p>
  HTML
)

seed_page(
  title: "Newsletter",
  slug: "newsletter",
  layout: "simple",
  visible: true,
  position: 20,
  meta_title: "Newsletter — Cntrl+",
  meta_description: "Sign up for the Cntrl+ newsletter for updates and information.",
  body: <<~HTML
    <h1>Join the 1000's of active women ready to take back control.</h1>
    <p>Sign up to receive important updates and information about where you can get your Cntrl+.</p>
  HTML
)

seed_page(
  title: "Reviews",
  slug: "reviews",
  layout: "simple",
  visible: true,
  position: 21,
  meta_title: "Reviews — Cntrl+",
  meta_description: "Read reviews from real Cntrl+ customers.",
  body: <<~HTML
    <h1>Customer Reviews</h1>
    <p>Read what real customers are saying about Cntrl+ bladder support.</p>
  HTML
)

# -------------------------------------------------------------------------
# 5d. Blog Posts (layout: "blog", body = HTML string)
# -------------------------------------------------------------------------
puts "  --- Blog Posts ---"

blog_posts = [
  {
    title: "Let's Talk About It: 1 in 3 Women Experience Bladder Leaks. So Why Are We Still Whispering About It?",
    slug: "bladder-leaks-women-support",
    meta_description: "1 in 3 women experience bladder leaks. It's time to stop whispering and start talking about real solutions.",
    body: <<~HTML
      <h1>Let's Talk About It: 1 in 3 Women Experience Bladder Leaks.</h1>
      <p>According to research, approximately one in three women encounter bladder leaks during their lifetime. Despite this prevalence, the topic remains largely unaddressed in public discourse.</p>
      <p>Bladder leaks frequently occur during everyday activities. Physical movement or activity puts pressure on the bladder, and this can be triggered by coughing, laughing, running, or lifting. This type of leak is classified as stress urinary incontinence.</p>
      <p>Several factors can contribute, including pregnancy, childbirth, hormonal changes, aging, and high-impact physical activities. Experiencing leaks does not indicate a physical weakness but rather reflects normal biological responses to pressure changes.</p>
      <p>Traditionally, pads have been the standard solution. However, this approach merely manages the problem rather than addressing its root cause. Modern alternatives now exist that provide gentle internal support to help stabilize the bladder during activity.</p>
      <p>The common misconception is that leaks only affect older, inactive, or out-of-shape women. In reality, athletes and active individuals also experience this issue. The common factor is not physical weakness but simply being human.</p>
      <p>When women have better information, better solutions follow — ultimately restoring the confidence necessary for full participation in daily activities without fear.</p>
    HTML
  },
  {
    title: "Sorry, But We're Not Wearing Diapers to Yoga.",
    slug: "sorry-but-we-re-not-wearing-diapers-to-yoga",
    meta_description: "Bladder leaks are common, but the way they're marketed to us? Not empowering. Not liberating. Not even believable.",
    body: <<~HTML
      <h1>Sorry, But We're Not Wearing Diapers to Yoga.</h1>
      <p>Picture the typical commercial: a woman in white pants, laughing with her friends, doing yoga in a meadow, maybe even skydiving — all while confidently wearing what looks suspiciously like an adult diaper.</p>
      <p>Bladder leaks are common, but the way they're marketed to us? Not empowering. Not liberating. Not even believable. It's like being told you can "still be sexy" in snow pants.</p>
      <h2>The Problem: We've Been Taught to Manage, Not Fix</h2>
      <p>The message has always been: wear this pad the size of a throw pillow and go live your best life. But existing products don't solve the problem. They just absorb it. Literally.</p>
      <p>Cntrl+ takes a different approach. It's soft, flexible, reusable, and internal. It moves with you, providing support — not surrender — and preventing leaks rather than disguising them.</p>
    HTML
  },
  {
    title: "The Real Reason Women Are Quitting the Gym",
    slug: "bladder-leaks-the-fitness-plot-twist-nobody-asked-for",
    meta_description: "7 in 10 women quit the gym before they hit 40 because of bladder leaks. It's time to change that.",
    body: <<~HTML
      <h1>The Real Reason Women Are Quitting the Gym? Two Words: Bladder Leaks.</h1>
      <p>7 in 10 women quit the gym, running, or sports before they even hit 40 because of bladder leaks. 1 in 3 women stop sports entirely for the same reason.</p>
      <p>This is a systemic problem, not an individual weakness. When women withdraw from exercise due to urinary incontinence, broader consequences ripple through families, communities, and economies.</p>
      <p>The costs go beyond fitness: loss of cardiovascular health, bone density, and strength. Beyond the physical, there are psychological impacts — anxiety, loss of athletic identity, and reduced freedom.</p>
      <p>If equivalent numbers of men experienced this issue, it would receive significantly more attention and resources. Urinary incontinence is not rare or shameful — it's a widespread crisis demanding acknowledgment and solutions.</p>
      <p>Women shouldn't need to choose between fitness and dignity.</p>
    HTML
  },
  {
    title: "Women's Health: Still a Niche? Hold My Pelvic Floor.",
    slug: "women-s-health-still-a-niche-hold-my-pelvic-floor",
    meta_description: "Women drive 80% of healthcare decisions. The global women's health market is projected to grow into hundreds of billions.",
    body: <<~HTML
      <h1>Women's Health: Still a Niche? Hold My Pelvic Floor.</h1>
      <p>Women comprise approximately half the global population. Dismissing their health needs as specialized contradicts basic demographics.</p>
      <p>Women's health encompasses far more than reproductive concerns — it includes preventative care, chronic disease management, mental health, and menopause support. The global women's health market is projected to grow into the hundreds of billions over the next decade.</p>
      <p>Despite women driving nearly 80% of healthcare decisions for their families, women-focused health innovation received only 3.3% of U.S. digital health funding between 2011–2020.</p>
      <p>Women were routinely left out of clinical trials until 1993 due to perceived complications. This legacy created a system where drugs and devices tested mostly on men were subsequently administered to women.</p>
      <p>These historical gaps are not evidence of niche status but markers of overlooked opportunity. Innovations addressing women's health often benefit broader populations through improved diagnostics and preventative care approaches.</p>
    HTML
  },
  {
    title: "Comfort = Performance: Why Soft, Flexible Support Wins.",
    slug: "comfort-performance-why-soft-flexible-support-wins",
    meta_description: "Traditional pessaries are hard, rigid, and uncomfortable. Cntrl+ is the sports bra for your pelvic floor.",
    body: <<~HTML
      <h1>Comfort = Performance: Why Soft, Flexible Support Wins.</h1>
      <p>Effective athletic equipment must move with the body, not against it. Rigid, inflexible gear creates maximum pain with zero performance.</p>
      <p>Traditional bladder solutions suffer the same problem: pads are bulky and scratchy, while traditional pessaries are hard, rigid, and uncomfortable. Cntrl+ is different — soft, flexible, and built to move with your body, functioning similarly to a tampon or menstrual cup for pelvic floor support.</p>
      <p>Cntrl+ is FDA-cleared, discreet, and comfortable enough that you forget it's there, while still providing leak prevention. When you feel supported and comfortable, you perform better — whether that's running, lifting, spinning, or just laughing without leaking.</p>
      <p>Think of it as the sports bra for your pelvic floor: snug, reliable, and quietly heroic.</p>
    HTML
  },
  {
    title: "Save the Planet, and Your Underwear.",
    slug: "save-the-planet-and-your-underwear-why-ditching-disposable-pads-is-the-glow-up-you-and-earth-deserve",
    meta_description: "The average woman uses 12,000–15,000 disposable pads in her lifetime. Each one contains plastic equal to four grocery bags.",
    body: <<~HTML
      <h1>Save the Planet, and Your Underwear.</h1>
      <p>The average woman will use 12,000–15,000 disposable pads or liners in her lifetime, with each pad containing approximately the amount of plastic found in four grocery bags. These products persist in landfills for centuries, eventually degrading into microplastics.</p>
      <p>Beyond environmental concerns, conventional disposables undergo bleaching processes and contain volatile organic compounds, phthalates, and PFAS — substances linked to hormone disruption and reproductive health issues.</p>
      <p>Cntrl+ is a reusable internal bladder support device made from medical-grade materials, free from harmful chemicals including PFAS and phthalates. FDA-cleared and washable, it can be reused approximately 90 times.</p>
      <p>Sustainable management aligns with both individual wellness and planetary health. Strength is reusable.</p>
    HTML
  },
  {
    title: "Bladder Leaks and Sports Bras: Hear Me Out.",
    slug: "bladder-leaks-and-sports-bras-hear-me-out-why-cntrl-is-like-a-sports-bra-for-your-pelvic-floor",
    meta_description: "CNTRL+ is the sports bra for your pelvic floor — supportive, reliable, and lets you move without worry.",
    body: <<~HTML
      <h1>Bladder Leaks and Sports Bras: Hear Me Out.</h1>
      <p>We've normalized plenty of uncomfortable aspects of women's lives, including jeans that double as shapewear and the acceptance that peeing yourself a little during spin class is "just part of being a woman."</p>
      <p>A quality sports bra provides supportive, reliable support that keeps everything where it should be and lets you move without worry. Cntrl+ offers similar functionality — the under-the-radar, under-the-waistband confidence-holding MVP — without the bulk of traditional disposable pads.</p>
      <p>Unlike conventional solutions, Cntrl+ is soft, flexible, internal, and discreet. It supports your urethra and pelvic floor to help prevent bladder leaks before they happen.</p>
      <p>Cntrl+ is made to last through up to 90 uses, requiring only washing and storage between applications. No more throwing pads in the trash every day.</p>
    HTML
  },
  {
    title: "Questions Your Doctor Should Be Asking After You Give Birth",
    slug: "did-you-just-have-a-baby-or-run-a-marathon-while-juggling-chainsaws-questions-your-doctor-should-be-asking-after-you-give-birth-but-probably-doesn-t",
    meta_description: "The postpartum checkup often neglects critical questions about bladder health and pelvic floor recovery.",
    body: <<~HTML
      <h1>Questions Your Doctor Should Be Asking After You Give Birth (But Probably Doesn't)</h1>
      <p>After childbirth, new mothers attend a six-week postpartum checkup expecting comprehensive discussion about physical recovery. Instead, conversations often focus narrowly on infant care: "How's baby sleeping?" and "Are you breastfeeding?" with minimal attention to maternal health.</p>
      <p>Physicians should ask about bladder leaks following childbirth. Stress urinary incontinence results when pregnancy and delivery stretch the pelvic floor, yet many providers dismiss this as routine.</p>
      <p>They should also ask about pelvic floor sensation — pressure, heaviness, or discomfort that helps assess whether structures remain properly supported.</p>
      <p>Providers should ask whether patients have abandoned activities they previously enjoyed — running, hiking, or yoga — due to physical limitations.</p>
      <p>Women deserve to feel in control of their bodies post-delivery. Recovery involves more than medical clearance; it encompasses returning to activities that make women feel strong and independent.</p>
    HTML
  },
  {
    title: "1 in 3 Women Have Bladder Leaks. So Why Are We All Pretending We Don't?",
    slug: "let-s-talk-about-it-1-in-3-women-have-bladder-leaks-so-why-are-we-all-pretending-we-don-t",
    meta_description: "1 in 3 women deal with bladder leaks, but society wants us to stay silent. Cntrl+ is changing that.",
    body: <<~HTML
      <h1>1 in 3 Women Have Bladder Leaks. So Why Are We All Pretending We Don't?</h1>
      <p>One in three women experience bladder leaks, yet society encourages silence rather than conversation. Bladder leaks represent more than a physical inconvenience — they disrupt daily life and confidence.</p>
      <p>This condition forces women to make calculated decisions about activities, constantly assessing bathroom proximity. Common solutions like pads, liners, and bulky underwear fail to address the actual problem effectively.</p>
      <p>Cntrl+ offers an alternative approach. Rather than external absorbent products, this solution functions as a reusable, flexible, internal support that works like a backup muscle. Insert it similarly to a tampon or menstrual cup, and engage in physical activities without worry.</p>
      <p>Addressing bladder leaks is a cultural shift. Ending stigma and normalizing conversations about bodily autonomy and pelvic health — that's a power move.</p>
    HTML
  },
  {
    title: "Taking Back Control: A Revolutionary Solution for Bladder Leaks.",
    slug: "taking-back-control-a-revolutionary-solution-for-bladder-leaks",
    meta_description: "Outdated solutions no longer cut it. Cntrl+ is a reusable, washable product that works like an extra muscle.",
    body: <<~HTML
      <h1>Taking Back Control: A Revolutionary Solution for Bladder Leaks.</h1>
      <p>Bladder leaks disrupt daily life, affecting confidence during physical activities like jogging and yoga. Women have increasingly avoided activities they enjoy due to inadequate solutions.</p>
      <p>Traditional options — disposable pads, liners, and bulky underwear — are uncomfortable and wasteful, providing only symptomatic relief rather than genuine solutions.</p>
      <p>Cntrl+ is a reusable, washable product that works like an extra muscle, helping stop leaks before they happen. It promises comfort and discretion while accommodating active lifestyles — from jogging to CrossFit to skiing.</p>
      <p>Cntrl+ eliminates waste associated with disposable products and empowers women to reclaim confidence and freedom in daily activities without constant worry about leaks.</p>
    HTML
  }
]

blog_posts.each_with_index do |attrs, idx|
  seed_page(attrs.merge(
    layout: "blog",
    visible: true,
    position: 22 + idx,
    meta_title: attrs[:title]
  ))
end

# -------------------------------------------------------------------------
# 5e. Blog Index (layout: "blog_index")
# -------------------------------------------------------------------------
puts "  --- Blog Index ---"

seed_page(
  title: "Insights",
  slug: "insights",
  layout: "blog_index",
  visible: true,
  position: 32,
  meta_title: "Insights — Cntrl+ Blog",
  meta_description: "Read articles about bladder health, women's wellness, and the Cntrl+ mission.",
  body: "<h1>Insights</h1><p>Read articles about bladder health, women's wellness, and the Cntrl+ mission.</p>"
)

# ╔═════════════════════════════════════════════════════════════════════════════╗
# ║  SUMMARY                                                                  ║
# ╚═════════════════════════════════════════════════════════════════════════════╝
puts "\n=== Seed Summary ==="
puts "  Stores:           #{Spree::Store.count}"
puts "  Products:         #{Spree::Product.count}"
puts "  Variants:         #{Spree::Variant.where.not(is_master: true).count}"
puts "  Menu Locations:   #{MenuLocation.count}"
puts "  Menu Items:       #{MenuItem.count}"
puts "  Homepage Sections:#{HomepageSection.count}"
puts "  Pages:            #{Spree::Page.count}"
puts "\nDone!"
