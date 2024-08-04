menu_location_ids = MenuLocation.pluck(:id)
(1..50).each do |i|
  MenuItem.create!(
    name: Faker::Lorem.word.capitalize,
    url: Faker::Internet.url,
    item_class: Faker::Lorem.word,
    item_id: Faker::Number.unique.number(digits: 5).to_s,
    item_target: ['_blank', '_self'].sample,
    parent_id: [nil, (1..10).to_a.sample].sample,
    position: i,
    is_visible: [true, false].sample,
    menu_location_id: menu_location_ids.sample, # Reference an existing MenuLocation ID
    created_at: Time.now,
    updated_at: Time.now
  )
end