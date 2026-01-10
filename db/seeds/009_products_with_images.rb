# Seed products with images from Teddy Fresh
# This creates sample products with real imagery

require 'open-uri'

# Helper method to attach image from URL
def attach_image_from_url(product, image_url, alt_text = nil)
  begin
    downloaded_image = URI.open(image_url)
    filename = File.basename(URI.parse(image_url).path)
    
    product.images.create!(
      attachment: {
        io: downloaded_image,
        filename: filename
      },
      alt: alt_text || product.name
    )
    puts "✓ Attached image to #{product.name}"
  rescue => e
    puts "✗ Failed to attach image to #{product.name}: #{e.message}"
  end
end

# Create products based on Teddy Fresh catalog
products_data = [
  {
    name: "Sketches Tapestry Puffer",
    description: "Multi-colored puffer jacket with unique tapestry design",
    price: 146.00,
    sku: "TF-PUFFER-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF_Puffer-Front_SQUARE.jpg?v=1764610814&width=600"
  },
  {
    name: "Plaid Patchwork Dress",
    description: "Stylish plaid patchwork dress with vintage-inspired design",
    price: 85.00,
    sku: "TF-DRESS-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/plaid_dress.jpg?v=1762306683&width=600"
  },
  {
    name: "I'm Hot Firetruck Sweater",
    description: "Black sweater with playful firetruck graphic design",
    price: 85.00,
    sku: "TF-SWEATER-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Im_Hot_Firetruck_Sweater_Front_Web-Res.jpg?v=1762208883&width=600"
  },
  {
    name: "Pleated Corduroy Pant",
    description: "Green pleated corduroy pants with comfortable fit",
    price: 75.00,
    sku: "TF-PANT-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/pleated_corduroy_pants.jpg?v=1762306578&width=600"
  },
  {
    name: "Logo Terry Tee",
    description: "Purple terry cloth tee with logo design",
    price: 65.00,
    sku: "TF-TEE-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Blocky_Letters_Terry_Tee_Web-Res.jpg?v=1762209505&width=600"
  },
  {
    name: "Chunky Pom Pom Beanie",
    description: "Multi-colored beanie with chunky pom pom detail",
    price: 26.00,
    sku: "TF-BEANIE-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Chunky_Pom_Pom_Web-Res.jpg?v=1762209157&width=600"
  },
  {
    name: "Black Marble Wash Hoodie",
    description: "Black hoodie with unique marble wash effect",
    price: 90.00,
    sku: "TF-HOODIE-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Black_Marble_Hoodie_Web-Res.jpg?v=1762209235&width=600"
  },
  {
    name: "Black Marble Wash Shorts",
    description: "Matching black shorts with marble wash effect",
    price: 70.00,
    sku: "TF-SHORTS-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Black_Marble_Short_Web-Res.jpg?v=1762209413&width=600"
  },
  {
    name: "Strawberry Pointelle Cardigan",
    description: "White multi-color cardigan with strawberry pattern",
    price: 45.00,
    sku: "TF-CARDIGAN-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Little_Print_Pointelle_Cardigan_Web-Res-v2.jpg?v=1762209655&width=600"
  },
  {
    name: "Strawberry Pointelle Tank",
    description: "White multi-color tank top with strawberry pattern",
    price: 30.00,
    sku: "TF-TANK-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/251030_Little_Print_Pointelle_Tank_Web-Res-v2.jpg?v=1762209572&width=600"
  },
  {
    name: "Classic Washed Tee",
    description: "Classic washed t-shirt available in multiple colors",
    price: 22.00,
    sku: "TF-TEE-002",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF25K102GREYFRONT_6fc08d72-d1bd-4a2e-a1cb-76d06c67f557.jpg?v=1752103116&width=600"
  },
  {
    name: "Classic Washed Boxy Hoodie",
    description: "Comfortable boxy fit hoodie with washed finish",
    price: 63.00,
    sku: "TF-HOODIE-002",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF25K106FRONTBLACK_5a8c8c8d-75b2-444a-a47b-d0f5e352b8a5.jpg?v=1753401758&width=600"
  },
  {
    name: "Classic Washed Pocket Tee",
    description: "Classic tee with pocket detail and washed finish",
    price: 23.00,
    sku: "TF-TEE-003",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF25K103FRONTBLACK_8744bd26-97b91-4dbe-9f64-2867be573075.jpg?v=1752102783&width=600"
  },
  {
    name: "Classic Washed Sweatpants",
    description: "Comfortable sweatpants with washed finish",
    price: 56.00,
    sku: "TF-PANTS-002",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF25K110-GREEN-SQUARE.jpg?v=1764094504&width=600"
  },
  {
    name: "Dark Knight Hoodie",
    description: "Black hoodie with Dark Knight themed design",
    price: 75.00,
    sku: "TF-HOODIE-003",
    image_url: "https://teddyfresh.com/cdn/shop/files/250925_TeddyFresh_Dark-Knight-Hoodie_SQUARE.jpg?v=1758843423&width=600"
  },
  {
    name: "Cloud Dye Shorts",
    description: "Blue multi-color shorts with cloud dye effect",
    price: 62.00,
    sku: "TF-SHORTS-002",
    image_url: "https://teddyfresh.com/cdn/shop/files/250804_TeddyFresh_Cloud_ShortsSQUARE.jpg?v=1757023710&width=600"
  },
  {
    name: "Textured Fabric Shirt",
    description: "Multi-colored textured fabric shirt",
    price: 65.00,
    sku: "TF-SHIRT-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF_Plaid_Woven_Shirt_Front_SQUARE.jpg?v=1759514974&width=600"
  },
  {
    name: "Scallop Trim Dress",
    description: "Blue dress with decorative scallop trim detail",
    price: 68.00,
    sku: "TF-DRESS-002",
    image_url: "https://teddyfresh.com/cdn/shop/files/Scallop_Trim_Dress_SQUARE.jpg?v=1755286045&width=600"
  },
  {
    name: "My Kid Can Draw This Tee",
    description: "Fun graphic tee with playful design",
    price: 36.00,
    sku: "TF-TEE-004",
    image_url: "https://teddyfresh.com/cdn/shop/files/medium03633.jpg?v=1753289302&width=600"
  },
  {
    name: "Metallic Bear Bag",
    description: "Silver metallic bag with bear design",
    price: 80.00,
    sku: "TF-BAG-001",
    image_url: "https://teddyfresh.com/cdn/shop/files/TF24BAG09front1_ccb6a74f-b995-4362-a903-003a88560a71.jpg?v=1738777401&width=600"
  }
]

puts "Creating products with images..."
puts "=" * 50

# Create default taxonomy and taxon if they don't exist
taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Categories") do |t|
  t.position = 0
end

clothing_taxon = taxonomy.root.children.find_or_create_by!(name: "Clothing") do |t|
  t.taxonomy = taxonomy
  t.permalink = "categories/clothing"
end

accessories_taxon = taxonomy.root.children.find_or_create_by!(name: "Accessories") do |t|
  t.taxonomy = taxonomy
  t.permalink = "categories/accessories"
end

# Create shipping category if it doesn't exist
shipping_category = Spree::ShippingCategory.find_or_create_by!(name: "Default")

products_data.each do |product_data|
  # Skip if product with this SKU already exists
  if Spree::Product.exists?(sku: product_data[:sku])
    puts "⊘ Skipping #{product_data[:name]} (already exists)"
    next
  end

  begin
    # Create the product
    product = Spree::Product.create!(
      name: product_data[:name],
      description: product_data[:description],
      price: product_data[:price],
      available_on: Time.current,
      shipping_category: shipping_category,
      sku: product_data[:sku]
    )

    # Add to appropriate taxon
    taxon = product_data[:name].downcase.include?('bag') ? accessories_taxon : clothing_taxon
    product.taxons << taxon

    # Create master variant with stock
    product.master.stock_items.first&.update(count_on_hand: rand(10..100))

    # Attach image from URL
    attach_image_from_url(product, product_data[:image_url], product_data[:name])

    puts "✓ Created product: #{product.name} ($#{product.price})"
  rescue => e
    puts "✗ Failed to create #{product_data[:name]}: #{e.message}"
  end
end

puts "=" * 50
puts "✓ Product seeding complete!"
puts "Total products in database: #{Spree::Product.count}"
