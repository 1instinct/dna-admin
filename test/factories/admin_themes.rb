FactoryBot.define do
  factory :admin_theme do
    brand_name { 'Test Admin' }
    primary_color { '#6366f1' }
    secondary_color { '#8b5cf6' }
    surface_color { '#1a1a2e' }
    background_color { '#0f0f1a' }
    text_color { '#e2e8f0' }
    sidebar_color { '#16162a' }
    border_radius { '8px' }
    font_family { 'Inter, system-ui, sans-serif' }
    color_mode { 'system' }
    enable_animations { true }
    singleton_guard { 0 }
  end
end
