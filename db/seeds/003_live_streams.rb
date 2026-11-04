20.times do
  LiveStream.create!(
    title: FFaker::Lorem.sentence,
    description: FFaker::Lorem.paragraph,
    stream_url: FFaker::Internet.uri('https'),
    stream_key: SecureRandom.hex(5),
    stream_id: rand(10000..99999),
    playback_ids: Array.new(3) { SecureRandom.hex(5) },
    status: %w[active inactive].sample,
    start_date: Time.now + rand(1..30).days,
    is_active: [true, false].sample,
    created_at: Time.now,
    updated_at: Time.now,
    actor_id: Spree::User.pluck(:id).sample
  )
end
