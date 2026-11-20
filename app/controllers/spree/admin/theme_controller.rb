class Spree::Admin::ThemeController < Spree::Admin::BaseController
  def show
    @theme = AdminTheme.first_or_initialize
    @theme.save! if @theme.new_record?
  end

  def update
    @theme = AdminTheme.first_or_create!
    @theme.assign_attributes(theme_params)
    @theme.logo.attach(params[:admin_theme][:logo]) if params.dig(:admin_theme, :logo)
    @theme.favicon.attach(params[:admin_theme][:favicon]) if params.dig(:admin_theme, :favicon)

    if params[:admin_theme][:remove_logo] == '1' && @theme.logo.attached?
      @theme.logo.purge
    end
    if params[:admin_theme][:remove_favicon] == '1' && @theme.favicon.attached?
      @theme.favicon.purge
    end

    if @theme.save
      AdminTheme.bust_cache!
      flash[:success] = Spree.t('admin.theme.updated')
      redirect_to admin_theme_path
    else
      flash.now[:error] = @theme.errors.full_messages.join(', ')
      render :show
    end
  end

  private

  def theme_params
    params.require(:admin_theme).permit(
      :brand_name, :primary_color, :secondary_color, :surface_color,
      :background_color, :text_color, :sidebar_color, :border_radius,
      :font_family, :color_mode, :enable_animations, :custom_css
    )
  end
end
