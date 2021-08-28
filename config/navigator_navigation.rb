SimpleNavigation::Configuration.run do |navigation|
  # Use the spree_navigator custom renderer
  navigation.renderer = Navigator::Renderer::List

  # Class to be applied to active navigation items
  navigation.selected_class = 'selected'

  # Class to be applied to the current leaf of active navigation items
  navigation.active_leaf_class = 'active-leaf'

  # Turn off generation of li ID's. spree_navigator is doing its own
  navigation.autogenerate_item_ids = false

  # Turn on auto highlight feature
  navigation.auto_highlight = true
end
