class ThreadTable < ApplicationRecord
  has_many :live_streams, dependent: :destroy
end
