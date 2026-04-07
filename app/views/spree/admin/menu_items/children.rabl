collection @menu_items, object_root: false
node(:data) { |menu_item| menu_item.name }
node(:attr) do |menu_item|
  {
    id:   menu_item.id,
    name: menu_item.name
  }
end
node(:state) { 'closed' }
