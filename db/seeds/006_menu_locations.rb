unless MenuLocation.count > 0
  (1..5).each do |i|
    MenuLocation.create!(
      title: "Menu Location #{i}",
      location: "menu_location_#{i}",
      is_visible: true
    )
  end
end