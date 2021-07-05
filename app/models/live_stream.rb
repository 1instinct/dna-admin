class LiveStream < ApplicationRecord
  has_many :live_stream_products, dependent: :destroy
  has_many :products, class_name: 'Spree::Product', through: :live_stream_products, dependent: :destroy
end
