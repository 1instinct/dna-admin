50.times do
  Message.create!(
    is_received: [true, false].sample,
    is_read: [true, false].sample,
    sentiment: rand(-1..1),
    created_at: Time.now,
    updated_at: Time.now,
    sender_type: 'User',
    sender_id: Spree::User.pluck(:id).sample,
    receiver_type: 'User',
    receiver_id: Spree::User.pluck(:id).sample,
    thread_table_id: (1..10).to_a.sample,
    message: Faker::Lorem.sentence
  )
end