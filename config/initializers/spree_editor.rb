# Use CKEditor 4.22.1 (last free version before LTS licensing)
# This overrides the default CKEditor version from spree_editor gem

if defined?(Spree::Editor)
  Spree::Editor.configure do |config|
    # Use CKEditor 4.22.1 (last free version)
    config.editor_class = 'ckeditor'
    config.editor_version = '4.22.1'
    
    # Configure CKEditor to use CDN with free version
    config.cdn_url = 'https://cdn.ckeditor.com/4.22.1/standard/ckeditor.js'
    
    # Editor configuration options
    config.toolbar = [
      ['Bold', 'Italic', 'Underline', 'Strike'],
      ['NumberedList', 'BulletedList', '-', 'Outdent', 'Indent'],
      ['Link', 'Unlink', 'Anchor'],
      ['Image', 'Table', 'HorizontalRule', 'SpecialChar'],
      ['Format', 'FontSize'],
      ['TextColor', 'BGColor'],
      ['Maximize', '-', 'Source']
    ]
    
    # Additional settings
    config.height = '400px'
    config.language = 'en'
  end
end

# Alternative: If the above doesn't work, we can override the CKEditor JavaScript include
# by creating a custom view override for the editor inclusion
