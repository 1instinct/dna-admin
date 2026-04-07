class Spree::Admin::MenuLocationsController <  Spree::Admin::BaseController
	before_action :set_session

	def index
    @q = MenuLocation.ransack(params[:q])
		@collection = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(params[:per_page])
	end

	def new
		@menu_location = MenuLocation.new
	end

	def edit
		@menu_location = MenuLocation.find(params[:id])
	end

	def update
		@menu_location = MenuLocation.find(params[:id])
		respond_to do |format|
			if @menu_location.update(menu_location_params)
				flash[:success] = Spree.t('menu_location.success.update')
				format.html { redirect_to admin_menu_location_path }
			else
				flash[:error] = @message.errors.full_messages.join(', ')
				format.html { render :edit }
			end
		end
	end

	def show
		@menu_location = MenuLocation.find(params[:id])
	end

	def create
		@menu_location = MenuLocation.new(menu_location_params)
		if @menu_location.save
			flash[:success] = Spree.t('menu_location.success.create')
			redirect_to admin_menu_locations_path
		else
			flash[:error] = @menu_location.errors.full_messages.join(', ')
			format.html { render :new }
		end
	end

	def destroy
		@menu_location = MenuLocation.find(params[:id])
		if @menu_location.destroy
			flash[:success] = Spree.t('menu_location.success.delete')
			respond_with do |format|
				format.html { redirect_to collection_url }
				format.js  { render_js_for_destroy }
			end
		else
			flash[:error] = @response[1]['error']['messages'].join("")
			redirect_to admin_menu_location_path
		end
	end
	private
	def set_session
		session[:return_to] = request.url
	end
	def menu_location_params
		params.require(:menu_location).permit(:title, :location, :is_visible)
	end
end
