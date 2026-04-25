module AdminThemeHelper
  def sanitize_css(css)
    return '' if css.blank?
    AdminTheme::DANGEROUS_CSS_PATTERNS.each do |pattern|
      css = css.gsub(pattern, '')
    end
    css
  end

  def theme_font_url(font_family)
    font_name = font_family.to_s.split(',').first.strip
    return nil if font_name.blank? || font_name.start_with?('system')
    "https://fonts.googleapis.com/css2?family=#{font_name.gsub(' ', '+')}:wght@400;500;600;700&display=swap"
  end
end
