module DigitalAssets
  # Computes the SHA-256 of a digital asset's files after upload (Spree::DigitalAsset#store_checksums!).
  class ChecksumJob < ApplicationJob
    queue_as :default

    def perform(asset_id)
      Spree::DigitalAsset.find_by(id: asset_id)&.store_checksums!
    end
  end
end
