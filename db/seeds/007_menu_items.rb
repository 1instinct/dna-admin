menu_location_ids = MenuLocation.pluck(:id)

menu_items = [
  { name: 'Home', url: '/', item_class: 'nav-home' },
  { name: 'Shop', url: '/products', item_class: 'nav-shop' },
  { name: 'New Arrivals', url: '/t/new-arrivals', item_class: 'nav-new' },
  { name: 'Sale', url: '/t/sale', item_class: 'nav-sale' },
  { name: 'Collections', url: '/t/collections', item_class: 'nav-collections' },
  { name: 'Live Shopping', url: '/live-streams', item_class: 'nav-live' },
  { name: 'About Us', url: '/pages/about-us', item_class: 'nav-about' },
  { name: 'Contact', url: '/pages/contact', item_class: 'nav-contact' }
]

menu_items.each_with_index do |item_data, i|
  MenuItem.create!(
    name: item_data[:name],
    url: item_data[:url],
    item_class: item_data[:item_class],
    item_id: (i + 1).to_s,
    item_target: '_self',
    parent_id: nil,
    position: i,
    is_visible: true,
    menu_location_id: menu_location_ids.first,
    created_at: Time.now,
    updated_at: Time.now
  )
end