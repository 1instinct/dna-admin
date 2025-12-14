20.times do
  LiveStream.create!(
    title: Faker::Lorem.sentence(word_count: 3),
    description: Faker::Lorem.paragraph,
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