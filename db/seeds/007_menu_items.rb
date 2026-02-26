menu_location_ids = MenuLocation.pluck(:id)
(1..20).each do |i|
  MenuItem.create!(
    name: FFaker::Lorem.word.capitalize,
    url: FFaker::Internet.uri('https'),
    item_class: FFaker::Lorem.word,
    item_id: rand(10000..99999).to_s,
    item_target: ['_blank', '_self'].sample,
    parent_id: [nil, (1..10).to_a.sample].sample,
    position: i,
    is_visible: [true, false].sample,
    menu_location_id: menu_location_ids.sample, # Reference an existing MenuLocation ID
    created_at: Time.now,
    updated_at: Time.now
  )
end
