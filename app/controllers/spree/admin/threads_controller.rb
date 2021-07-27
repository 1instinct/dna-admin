class Spree::Admin::ThreadsController <  Spree::Admin::BaseController
	before_action :set_session

	def index
		@q = ThreadTable.ransack(params[:q])
		@collection = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(params[:per_page])
	end

	def new
		@thread = ThreadTable.new
	end

	def edit
		@thread = ThreadTable.find(params[:id])
	end

	def update
		@thread = ThreadTable.find(params[:id])
		respond_to do |format|
			if @thread.update(thread_params)
				flash[:success] = Spree.t('thread.success.update')
				format.html { redirect_to admin_thread_path }
			else
				flash[:error] = @thread.errors.full_threads.join(', ')
				format.html { render :edit }
			end
		end
	end

	def show
		@thread = ThreadTable.find(params[:id])
	end

	def create
		@thread = ThreadTable.new(thread_params)
		if @thread.save
			flash[:success] = Spree.t('thread.success.create')
			redirect_to admin_threads_path
		else
			flash[:error] = @thread.errors.full_threads.join(', ')
			format.html { render :new }
		end
	end

	def destroy
		@thread = ThreadTable.find(params[:id])
		if @thread.destroy
			flash[:success] = Spree.t('thread.thread.delete')
			respond_with do |format|
				format.html { redirect_to collection_url }
				format.js  { render_js_for_destroy }
			end
		else
			flash[:error] = @response[1]['error']['threads'].join("")
			redirect_to admin_thread_path
		end
	end
	private
	def set_session
		session[:return_to] = request.url
	end
	def thread_params
		params.require(:thread_table).permit(:archived, :stale)
	end
end
