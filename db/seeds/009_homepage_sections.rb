# Create homepage sections with various section types
puts "Creating homepage sections..."

sections_data = [
  {
    title: "Hero Banner",
    section_type: "hero",
    content: "<h1>Welcome to Our Store</h1><p>Discover amazing products at great prices</p>",
    position: 1,
    is_visible: true,
    settings: {
      background_image: "/images/hero-bg.jpg",
      button_text: "Shop Now",
      button_link: "/products",
      text_color: "#ffffff",
      overlay_opacity: 0.5
    }
  },
  {
    title: "Featured Products",
    section_type: "products",
    content: "<h2>Featured Products</h2><p>Check out our hand-picked selection</p>",
    position: 2,
    is_visible: true,
    settings: {
      product_ids: [],
      display_style: "grid",
      items_per_row: 4,
      show_price: true,
      show_add_to_cart: true
    }
  },
  {
    title: "Why Choose Us",
    section_type: "features",
    content: "<h2>Why Shop With Us</h2>",
    position: 3,
    is_visible: true,
    settings: {
      features: [
        { icon: "truck", title: "Free Shipping", description: "On orders over $50" },
        { icon: "shield", title: "Secure Payment", description: "100% secure transactions" },
        { icon: "refresh", title: "Easy Returns", description: "30-day return policy" },
        { icon: "support", title: "24/7 Support", description: "Dedicated customer service" }
      ]
    }
  },
  {
    title: "About Our Brand",
    section_type: "content",
    content: "<h2>Our Story</h2><p>We're passionate about bringing you the finest products with exceptional service. Founded in 2020, we've grown to become a trusted name in e-commerce.</p><p>Our mission is to provide quality products that enhance your lifestyle while delivering an outstanding shopping experience.</p>",
    position: 4,
    is_visible: true,
    settings: {
      layout: "two_column",
      image: "/images/about-us.jpg",
      image_position: "right"
    }
  },
  {
    title: "Customer Testimonials",
    section_type: "testimonials",
    content: "<h2>What Our Customers Say</h2>",
    position: 5,
    is_visible: true,
    settings: {
      testimonials: [
        { 
          name: "Sarah Johnson", 
          rating: 5, 
          text: "Amazing quality and fast shipping! Will definitely order again.",
          avatar: "/images/avatar1.jpg"
        },
        { 
          name: "Mike Chen", 
          rating: 5, 
          text: "Great customer service and excellent products. Highly recommend!",
          avatar: "/images/avatar2.jpg"
        },
        { 
          name: "Emma Davis", 
          rating: 5, 
          text: "Love everything I've ordered. The quality is outstanding!",
          avatar: "/images/avatar3.jpg"
        }
      ],
      display_style: "carousel"
    }
  },
  {
    title: "Newsletter Signup",
    section_type: "newsletter",
    content: "<h2>Stay Updated</h2><p>Subscribe to our newsletter for exclusive deals and updates</p>",
    position: 6,
    is_visible: true,
    settings: {
      background_color: "#f8f9fa",
      button_text: "Subscribe",
      privacy_text: "We respect your privacy and won't spam you",
      show_social_links: true
    }
  },
  {
    title: "Image Gallery",
    section_type: "gallery",
    content: "<h2>Follow Us on Instagram</h2>",
    position: 7,
    is_visible: false,  # Hidden by default
    settings: {
      images: [],
      columns: 4,
      spacing: 10,
      enable_lightbox: true
    }
  },
  {
    title: "Special Offer Banner",
    section_type: "call_to_action",
    content: "<h2>Limited Time Offer!</h2><p>Get 20% off your first purchase</p>",
    position: 8,
    is_visible: true,
    settings: {
      background_color: "#007bff",
      text_color: "#ffffff",
      button_text: "Shop Now",
      button_link: "/products",
      countdown_enabled: false
    }
  }
]

sections_data.each_with_index do |data, index|
  HomepageSection.create!(data)
  puts "Created section #{index + 1}: #{data[:title]}"
end

puts "Homepage sections created successfully!"
puts "- #{HomepageSection.count} total sections"
puts "- #{HomepageSection.visible.count} visible sections"
