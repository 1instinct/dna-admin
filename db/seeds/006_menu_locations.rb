unless MenuLocation.count > 0
  (1..5).each do |i|
    MenuLocation.create!(
      name: Faker::Lorem.word.capitalize,
      location_type: ['header', 'footer'].sample,
      created_at: Time.now,
      updated_at: Time.now
    )
  end
end