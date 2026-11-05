module Spree
  module Admin
    class MenuItemsController < Spree::Admin::BaseController
      before_action :set_menu_item, only: [:edit, :update, :destroy, :children]

      def index
         @menu_items = MenuItem.top_level
         @menu_location = MenuLocation.all

         if params[:menu_location_id].present?
           @menu_items = MenuLocation.find_by(id: params[:menu_location_id].to_i).menu_items
         end
          respond_to do |format|
            format.html
            format.json { render :children, status: :ok }
          end
      end

      def new
        @menu_location = MenuLocation.all
        @menu_item = MenuItem.new
      end

      def create
        @menu_item = MenuItem.new(menu_item_params)
        respond_to do |format|
          if @menu_item.save
            format.html { submit_success_redirect(:create) }
            format.json { render :show, status: :created }
          else
            format.html { render :new }
            format.json { render_json_error }
          end
        end
      end

      def update
        respond_to do |format|
          if @menu_item.update(menu_item_params)
            organize_items
            format.html { submit_success_redirect(:update) }
            format.json { render :show, status: :created }
          else
            format.html { render :edit }
            format.json { render_json_error }
          end
        end
      end

      def destroy
        @menu_item.destroy
        respond_to do |format|
          format.html { submit_success_redirect(:destroy) }
          format.json { head :no_content }
        end
      end

      def children
        @menu_items = MenuItem.find(params[:id]).childrens

        respond_to do |format|
          format.json { render :children, status: :ok }
        end
      end


      protected

      def submit_success_redirect(type)
        scope = 'menu_navigator.admin.flash.success'
        redirect_to admin_menu_items_path, flash: {
          success: Spree.t(type, name: @menu_item.name, scope: scope)
        }
      end

      def render_json_error
        render json: @menu_item.errors, status: :unprocessable_entity
      end

      def set_menu_item
        @menu_item = MenuItem.find(params[:id].to_i)
        @menu_location = MenuLocation.all
      end

      def permitted_menu_item_attributes
        [
          :name,
          :url,
          :item_id,
          :item_class,
          :item_target,
          :parent_id,
          :position,
          :menu_location_id
        ]
      end

      def menu_item_params
      if params[:menu_item][:parent_id] == 'menu_tree'
          params[:menu_item][:parent_id] = nil

      end
        params.require(:menu_item).permit(permitted_menu_item_attributes)
      end

      def organize_items
        MenuItem.where(parent_id: menu_item_params[:parent_id])
          .order(updated_at: :desc)
          .map(&:id)
          .each_with_index do |id, index|
          MenuItem.find(id).update(position: index)
        end
      end
    end
  end
end
