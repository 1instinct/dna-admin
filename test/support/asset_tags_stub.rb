# Request tests assert on page content, not compiled assets. The backend
# manifests (vendor/assets/*/spree/backend/all.*) require
# spree/backend/spree_promo_users_codes, whose gem is not in the bundle, so
# compiling them in tests fails. Emit plain tags without touching Sprockets.
module AssetTagsStub
  def stylesheet_link_tag(*sources)
    options = sources.extract_options!
    safe_join(sources.map { |s| tag(:link, rel: 'stylesheet', href: "/assets/#{s}.css", media: options[:media]) })
  end

  def javascript_include_tag(*sources)
    sources.extract_options!
    safe_join(sources.map { |s| content_tag(:script, '', src: "/assets/#{s}.js") })
  end
end

ActiveSupport.on_load(:action_view) { prepend AssetTagsStub }
