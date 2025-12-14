50.times do
  LiveStreamLike.create!(
    live_stream_id: (1..20).to_a.sample,
    user_id: Spree::User.pluck(:id).sample,
    created_at: Time.now,
    updated_at: Time.now
  )
end