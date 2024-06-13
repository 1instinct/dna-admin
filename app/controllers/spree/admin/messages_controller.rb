class Spree::Admin::MessagesController < Spree::Admin::BaseController
	before_action :set_session
  
	def index
	  @q = Message.ransack(params[:q])
	  @collection = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(params[:per_page])
	end
  
	def new
	  @message = Message.new
	end
  
	def edit
	  @message = Message.find(params[:id])
	end
  
	def update
	  @message = Message.find(params[:id])
	  respond_to do |format|
		if @message.update(message_params)
		  flash[:success] = Spree.t('message.success.update')
		  format.html { redirect_to admin_message_path }
		else
		  flash[:error] = @message.errors.full_messages.join(', ')
		  format.html { render :edit }
		end
	  end
	end
  
	def show
	  @message = Message.find(params[:id])
	end
  
	def create
	  @message = Message.new(message_params)
	  if @message.save
		flash[:success] = Spree.t('message.added_success')
		redirect_to admin_messages_path
	  else
		flash[:error] = @message.errors.full_messages.join(', ')
		format.html { render :new }
	  end
	end
  
	def destroy
	  @message = Message.find(params[:id])
	  if @message.destroy
		flash[:success] = Spree.t('message.message_deleted')
		respond_with do |format|
		  format.html { redirect_to collection_url }
		  format.js { render_js_for_destroy }
		end
	  else
		flash[:error] = @response[1]['error']['messages'].join("")
		redirect_to admin_message_path
	  end
	end
  
	def conversation
	  message = Message.find_by_id(params[:id])
	  @user_1 = message.sender
	  @user_2 = message.receiver
	  @one_to_one_messages = conversation_between_two_parties(message.sender, message.receiver)
	  @one_to_one_messages = Message.where(id: @one_to_one_messages.pluck(:id))
	  thread_ids = @one_to_one_messages.pluck(:thread_table_id).uniq
	  @threads = []
	  thread_ids.each do |thread_id|
		@threads << @one_to_one_messages.where(thread_table_id: thread_id)
	  end
	end
  
	private
  
	def set_session
	  session[:return_to] = request.url
	end
  
	def message_params
	  params.require(:message).permit(:is_received, :is_read, :sentiment, :sender_type, :sender_id, :receiver_type, :receiver_id, :message)
	end
  
	def collection(resource)
	  return @collection if @collection.present?
	  params[:q] ||= {}
	  @collection = resource.all
	  @search = @collection.ransack(params[:q])
	  @collection = @search.result.order(created_at: :desc).page(params[:page]).per(params[:per_page])
	end
  
	def conversation_between_two_parties(user_1, user_2)
	  user_1_sent_messages = user_1.sent_messages.where(receiver_id: user_2.id).where.not(thread_table_id: nil)
	  user_2_sent_messages = user_2.sent_messages.where(receiver_id: user_1.id).where.not(thread_table_id: nil)
	  all_messages = (user_1_sent_messages + user_2_sent_messages).sort { |a, b| a.created_at <=> b.created_at }
	end
  end
  
