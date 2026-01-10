live_streams = [
  {
    title: "New Collection Launch",
    description: "Join us for the exclusive reveal of our latest collection. Discover new styles, special offers, and get your questions answered live."
  },
  {
    title: "Product Showcase & Q&A",
    description: "Get an up-close look at our best-selling products. Ask questions, see styling tips, and learn about upcoming releases."
  },
  {
    title: "Behind the Scenes",
    description: "Take a tour of our design studio and see how we create our products from concept to completion."
  },
  {
    title: "Seasonal Sale Event",
    description: "Don't miss our biggest sale of the season! Shop exclusive deals and limited-time offers during this live shopping event."
  },
  {
    title: "Style Guide: Winter Essentials",
    description: "Learn how to style our winter collection with tips from our fashion experts. Perfect looks for every occasion."
  },
  {
    title: "Customer Favorites Spotlight",
    description: "We're featuring your most-loved products! See why these items are customer favorites and shop the collection."
  },
  {
    title: "New Arrivals Preview",
    description: "Be the first to see what's coming next. Preview upcoming releases and reserve your favorites before they sell out."
  },
  {
    title: "Flash Sale Friday",
    description: "Join us every Friday for surprise deals and flash sales. Limited quantities available, so shop fast!"
  },
  {
    title: "Meet the Designer",
    description: "Chat with our lead designer about the inspiration behind our latest collection and get insider design insights."
  },
  {
    title: "Holiday Gift Guide",
    description: "Find the perfect gifts for everyone on your list. We'll showcase our top picks and help you shop with confidence."
  }
]

live_streams.each do |stream_data|
  LiveStream.create!(
    title: stream_data[:title],
    description: stream_data[:description],
    stream_url: Faker::Internet.url,
    stream_key: Faker::Lorem.characters(number: 10),
    stream_id: Faker::Number.number(digits: 5),
    playback_ids: [Faker::Lorem.characters(number: 10), Faker::Lorem.characters(number: 10), Faker::Lorem.characters(number: 10)],
    status: %w[active inactive].sample,
    start_date: Faker::Time.forward(days: 30),
    is_active: [true, false].sample,
    created_at: Time.now,
    updated_at: Time.now,
    actor_id: Spree::User.pluck(:id).sample
  )
end