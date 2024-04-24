Spree::Image.class_eval do
  attachment_styles.clear
  attachment_sizes.clear

  # Add your custom styles here
  attachment_styles.merge!(
    mini: '48x48>',
    small: '100x100>',
    product: '240x240>',
    large: '600x600>'
  )

  # Add your custom sizes here
  attachment_sizes.merge!(
    mini: { width: 48, height: 48 },
    small: { width: 100, height: 100 },
    product: { width: 240, height: 240 },
    large: { width: 600, height: 600 },
    original: { }
  )
end
