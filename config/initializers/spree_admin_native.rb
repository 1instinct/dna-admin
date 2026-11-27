# Spree Admin Native companion gem: lets the mobile admin app (and its forks) pair by QR code,
# sends a push for every new order and serves the app's Home numbers.
# Admin page: /admin/admin_native_devices.
SpreeAdminNative.configure do |c|
  # Only needed if the Expo project enforces push security (Expo dashboard → Access tokens).
  c.expo_access_token = ENV['SPREE_ADMIN_NATIVE_EXPO_ACCESS_TOKEN'].presence
  c.low_stock_threshold = ENV.fetch('SPREE_ADMIN_NATIVE_LOW_STOCK', 2).to_i
  # The admin app's iOS bundle id. Admin app → App versions checks a minimum or recommended
  # version against what the App Store serves for it; without one the check is skipped. A fork
  # can also set it in its own initializer.
  ios_bundle_id = ENV['SPREE_ADMIN_NATIVE_IOS_BUNDLE_ID'].presence
  c.ios_bundle_id = ios_bundle_id if ios_bundle_id
end
