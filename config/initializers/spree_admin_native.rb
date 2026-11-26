# Spree Admin Native companion gem: lets the mobile admin app (and its forks) pair by QR code,
# sends a push for every new order and serves the app's Home numbers.
# Admin page: /admin/admin_native_devices.
SpreeAdminNative.configure do |c|
  # Only needed if the Expo project enforces push security (Expo dashboard → Access tokens).
  c.expo_access_token = ENV['SPREE_ADMIN_NATIVE_EXPO_ACCESS_TOKEN'].presence
  c.low_stock_threshold = ENV.fetch('SPREE_ADMIN_NATIVE_LOW_STOCK', 2).to_i
end
