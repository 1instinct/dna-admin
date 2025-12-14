50.times do
  LiveStreamProduct.create!(
    live_stream_id: (1..20).to_a.sample,
    product_id: Spree::Product.pluck(:id).sample,
    created_at: Time.now,
    updated_at: Time.now
  )
end