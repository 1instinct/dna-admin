module Spree
  module Admin
    # The menu builder: location tabs and one nested tree of items per location (MenuBuilder).
    #
    # HTML: GET /admin/menus?location=<id>, and the location forms (create, rename, delete).
    # JSON (the page's script, session auth with the CSRF token):
    #   GET   /admin/menus/:location_id/tree                 the nested items
    #   PATCH /admin/menus/:location_id/tree                 { nodes: [{ id, parent_id, position }] }
    #   POST  /admin/menus/:location_id/items                { menu_item: {...}, after_id? }
    #   PATCH /admin/menus/:location_id/items/:id            { menu_item: { name, link, item_target, is_visible } }
    #   DELETE /admin/menus/:location_id/items/:id           ?with_children=1 to delete an item with children
    # Refusals are 422 { error: { code, message } } and leave the tree unchanged.
    class MenusController < Spree::Admin::BaseController
      include AdminJsonEndpoints

      before_action :load_location, only: %i[tree move create_item update_item destroy_item update_location destroy_location]
      before_action :load_item, only: %i[update_item destroy_item]

      rescue_from MenuBuilder::Refused do |e|
        if json_request?
          render_json_error(e.code, e.message, e.status)
        else
          flash[:error] = e.message
          redirect_to spree.admin_menus_path
        end
      end

      def index
        @locations = MenuLocation.order(:created_at, :id).to_a
        @location = @locations.find { |l| l.id.to_s == params[:location].to_s } || @locations.first
        @link_kinds = MenuBuilder.link_kinds
      end

      def tree
        render json: { data: builder.tree, meta: { location: location_json(@location) } }
      end

      def move
        nodes = params.key?(:nodes) ? Array(params[:nodes]) : []
        render json: { data: builder.move!(nodes), meta: { location: location_json(@location) } }
      end

      def create_item
        item = builder.create!(item_params, after_id: params[:after_id])
        render json: { data: builder.present(item), tree: builder.tree }, status: :created
      end

      def update_item
        builder.update!(@item, item_params)
        render json: { data: builder.present(@item.reload), tree: builder.tree }
      end

      def destroy_item
        deleted = builder.destroy!(@item, with_children: ActiveModel::Type::Boolean.new.cast(params[:with_children]) == true)
        render json: { deleted: deleted, tree: builder.tree }
      end

      def create_location
        location = MenuLocation.new(location_params)
        location.is_visible = true if location.is_visible.nil?
        if location.save
          flash[:success] = "#{location.title} menu added."
          redirect_to spree.admin_menus_path(location: location.id)
        else
          flash[:error] = location.errors.full_messages.to_sentence
          redirect_to spree.admin_menus_path
        end
      end

      def update_location
        if @location.update(location_params)
          flash[:success] = "#{@location.title} menu saved."
        else
          flash[:error] = @location.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_menus_path(location: @location.id)
      end

      # Deletes the location and every item in it.
      def destroy_location
        MenuLocation.transaction do
          MenuItem.unscoped.where(menu_location_id: @location.id).delete_all
          @location.destroy!
        end
        flash[:success] = "#{@location.title} menu deleted."
        redirect_to spree.admin_menus_path
      end

      private

      # Authorized against MenuItem (authorize_admin), so a role that may manage menu items sees it.
      def model_class
        MenuItem
      end

      def builder
        @builder ||= MenuBuilder.new(@location)
      end

      def load_location
        @location = MenuLocation.find(params[:location_id] || params[:id])
      end

      def load_item
        @item = builder.items.find(params[:id])
      end

      # The link arrives as { kind, url, id }; the rest as the item's columns.
      def item_params
        raw = params.require(:menu_item)
        attrs = raw.permit(:name, :parent_id, :item_target, :is_visible).to_h
        attrs[:link] = raw[:link].respond_to?(:permit) ? raw[:link].permit(:kind, :url, :id).to_h : nil if raw.key?(:link)
        attrs
      end

      def location_params
        params.require(:menu_location).permit(:title, :location, :is_visible)
      end

      def location_json(location)
        { id: location.id.to_s, title: location.title, location: location.location, is_visible: location.is_visible != false }
      end
    end
  end
end
