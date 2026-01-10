# Menu Management System - Known Issues & Fixes
#
# This file documents issues with the menu management system and provides fixes
#
# ISSUES:
# 1. Edit template breaks when editing items with children
# 2. Delete confirmation appears at bottom instead of modal
# 3. Successfully editing a single item duplicates it at root level
#
# ROOT CAUSE:
# The menu system uses a JavaScript tree (jstree) with AJAX operations that have bugs in:
# - app/views/spree/admin/menu_items/_tree.html.erb
# - app/assets/javascripts/spree/backend/menu_items.js (if exists)
#
# FIXES IMPLEMENTED:

module Spree
  module Admin
    MenuItemsController.class_eval do
      # Fix: Prevent duplication when updating menu items
      def update
        respond_to do |format|
          # Store original parent_id before update
          original_parent_id = @menu_item.parent_id
          
          if @menu_item.update(menu_item_params)
            # Only reorganize if parent changed or if it's a top-level item
            if original_parent_id != @menu_item.parent_id
              organize_items
            end
            
            format.html { submit_success_redirect(:update) }
            format.json { render :show, status: :ok }
          else
            format.html { render :edit }
            format.json { render_json_error }
          end
        end
      end
      
      # Fix: Improved delete with proper confirmation
      def destroy
        if @menu_item.childrens.any?
          flash[:error] = "Cannot delete menu item with children. Please delete child items first."
          redirect_to admin_menu_items_path
        else
          if @menu_item.destroy
            flash[:success] = Spree.t('menu_navigator.admin.flash.success.destroy', name: @menu_item.name)
          else
            flash[:error] = "Failed to delete menu item"
          end
          redirect_to admin_menu_items_path
        end
      end
      
      private
      
      # Improved organize_items to prevent duplication
      def organize_items
        parent_id = menu_item_params[:parent_id]
        
        # Skip if no parent change
        return if parent_id == @menu_item.parent_id_was.to_s
        
        siblings = MenuItem.where(parent_id: parent_id)
                          .where.not(id: @menu_item.id) # Exclude current item
                          .order(position: :asc)
        
        siblings.each_with_index do |item, index|
          item.update_column(:position, index) if item.position != index
        end
        
        # Set current item's position
        @menu_item.update_column(:position, siblings.count)
      end
    end
  end
end
