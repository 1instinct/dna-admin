module AdminThemeHelper
  # Returns the custom CSS marked html_safe for output inside a <style> tag,
  # or an empty string if it fails the model's guard (which rejects any "<",
  # so "</style" can never appear in the output).
  def sanitize_css(css)
    return '' if css.blank? || AdminTheme.unsafe_css?(css)
    css.html_safe
  end

  def theme_font_url(font_family)
    font_name = font_family.to_s.split(',').first.strip
    return nil if font_name.blank? || font_name.start_with?('system')
    "https://fonts.googleapis.com/css2?family=#{font_name.gsub(' ', '+')}:wght@400;500;600;700&display=swap"
  end
end
