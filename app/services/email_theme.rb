# The customer email look, from config/email_theme.yml (see that file). Missing keys fall back to
# DNA's defaults, so a store's file only needs the values it changes.
#
#   EmailTheme.current[:accent]   # => "#eb8b8b"
module EmailTheme
  DEFAULTS = {
    color_scheme: 'light dark',
    page_bg: '#faece9', page_bg_dark: '#211a1c',
    pattern: '/email/pattern-light.png', pattern_dark: '/email/pattern-dark.png',
    card_bg: '#ffffff', card_bg_dark: '#2a2124', card_border: '#f0dcd7', card_border_dark: '#3a2e32',
    rule: '#f0dcd7', rule_dark: '#3d3034', radius: '18px',
    text: '#1a1a1a', text_dark: '#f3ecec', muted: '#6f6266', muted_dark: '#b9aaad',
    footer: '#7a6a6d', footer_dark: '#c9b9bc', footer_bg: '',
    accent: '#eb8b8b', accent_dark: '#f2a7a7', link: '#b84f4f', link_dark: '#f2a7a7',
    button_bg: '#1a1a1a', button_text: '#ffffff', button_bg_dark: '#eb8b8b', button_text_dark: '#1b0f10',
    badge_bg: '#ffffff', badge_border: '#ffffff', badge_shadow: '0 2px 10px rgba(80,40,50,0.12)',
    heading_font: "'IBM Plex Mono',Menlo,Consolas,monospace", body_font: 'Helvetica,Arial,sans-serif',
    default_logo: '', logo_height: 40
  }.freeze
  PATH = Rails.root.join('config', 'email_theme.yml')

  module_function

  # Read once per process in production; on every call elsewhere, so edits show up in previews.
  def current
    return @current if @current && Rails.env.production?

    @current = load_file
  end

  def load_file
    data = PATH.exist? ? YAML.safe_load(PATH.read) || {} : {}
    DEFAULTS.merge(data.to_h.symbolize_keys.slice(*DEFAULTS.keys).compact).freeze
  rescue Psych::Exception => e
    Rails.logger.error("[email_theme] #{PATH} is invalid (#{e.class}); using defaults")
    DEFAULTS
  end

  def always_dark?
    current[:color_scheme].to_s.strip == 'dark'
  end
end
