50.times do
  Contact.create!(
    actor_id: Spree::User.pluck(:id).sample,
    full_name: FFaker::Name.name,
    email: FFaker::Internet.email,
    phone: FFaker::PhoneNumber.phone_number.to_s,
    ip: FFaker::Internet.ip_v4_address,
    created_at: Time.now,
    updated_at: Time.now
  )
end