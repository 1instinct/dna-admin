require 'paperclip'

Paperclip::Attachment.default_options.update({
  styles: {
    mini: '48x48>',
    small: '100x100>',
    product: '240x240>',
    large: '600x600>',
    xl: '1000x1000>',
    widescreen: '1600x900>',
    portrait: '900x1600>'
  },
  default_style: :small,
  storage: :s3,
  s3_credentials: "#{Rails.root}/config/s3.yml",
  url: "/assets/products/:id/:style/:basename.:extension",
  path: ":rails_root/public/assets/products/:id/:style/:basename.:extension"
})
