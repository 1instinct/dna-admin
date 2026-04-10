ActiveRecord::Base.connection.reset_pk_sequence!(Spree::Page.table_name)

Spree::Page.find_or_create_by(slug: "about") do |page|
  page.title = "About"
  page.body = "Hey there everybody"
  page.show_in_header = true
  page.foreign_link = ""
  page.position = 0
  page.visible = true
  page.meta_keywords = "about, info"
  page.meta_description = "Everything about us."
  page.layout = "about"
  page.show_in_sidebar = true
  page.meta_title = "About"
  page.render_layout_as_partial = false
  page.show_in_footer = true
end