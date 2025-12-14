50.times do
  Contact.create!(
    actor_id: Spree::User.pluck(:id).sample,
    full_name: Faker::Name.name,
    email: Faker::Internet.email,
    phone: Faker::PhoneNumber.phone_number.to_s,
    ip: Faker::Internet.ip_v6_address,
    created_at: Time.now,
    updated_at: Time.now
  )
end