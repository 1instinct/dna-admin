class LiveStreamLike < ApplicationRecord
  belongs_to :live_stream
  belongs_to :user, class_name: 'Spree::User'
end
