module Spree
  module Admin
    class ContactsController < Spree::Admin::BaseController
      before_action :set_session

      def index
        collection(Contact)
    		respond_with(@collection)
      end

      def new
        @contact = Contact.new
      end

      def edit
        @contact = Contact.find(params[:id])
      end

      def update
        @contact = Contact.find(params[:id])
        respond_to do |format|
          if @contact.update(contact_params)
            flash[:success] = Spree.t('contact.success.update')
            format.html { redirect_to admin_contact_path }
          else
            flash[:error] = @contact.errors.full_messages.join(', ')
            format.html { render :edit }
          end
        end
      end

      def show
        @contact = Contact.find(params[:id])
      end

      def create
        @contact = Contact.new(contact_params)
        if @contact.save
          flash[:success] = Spree.t('contact.added_success')
          redirect_to admin_contacts_path
        else
          flash[:error] = @contact.errors.full_messages.join(', ')
          format.html { render :new }
        end
      end

      def destroy
        @contact = Contact.find(params[:id])
        if @contact.destroy
          flash[:success] = Spree.t('contact.contact_deleted')
          respond_with do |format|
            format.html { redirect_to collection_url }
            format.js  { render_js_for_destroy }
          end
        else
          flash[:error] = @response[1]['error']['messages'].join("")
          redirect_to admin_contact_path
        end
      end
      private
      def set_session
        session[:return_to] = request.url
      end
      def contact_params
        params.require(:contact).permit(:actor_id, :full_name, :email, :phone, :ip)
      end
      def collection(resource)
    		return @collection if @collection.present?

    		params[:q] ||= {}

    		@collection = resource.all
    		# @search needs to be defined as this is passed to search_form_for
    		@search = @collection.ransack(params[:q])
    		@collection = @search.result.order(created_at: :desc).page(params[:page]).per(params[:per_page])
    	end
    end
  end
end
