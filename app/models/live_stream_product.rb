class LiveStreamProduct < ApplicationRecord
  belongs_to :live_stream
  belongs_to :product, class_name: 'Spree::Product'
end
