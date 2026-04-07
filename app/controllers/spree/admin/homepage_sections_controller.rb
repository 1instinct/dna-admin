module Spree
  module Admin
    class HomepageSectionsController < Spree::Admin::BaseController
      before_action :set_homepage_section, only: [:edit, :update, :destroy, :show]
      
      def index
        @q = HomepageSection.ransack(params[:q])
        @collection = @q.result
                        .ordered
                        .page(params[:page])
                        .per(params[:per_page] || 25)
        @min_position = HomepageSection.minimum(:position) || 0
        @max_position = HomepageSection.maximum(:position) || 0
      end
      
      def new
        @homepage_section = HomepageSection.new
      end
      
      def create
        @homepage_section = HomepageSection.new(homepage_section_params)
        
        respond_to do |format|
          if @homepage_section.save
            flash[:success] = Spree.t('homepage_section.added_success')
            format.html { redirect_to admin_homepage_sections_path }
            format.json { render json: @homepage_section, status: :created }
          else
            flash[:error] = @homepage_section.errors.full_messages.join(', ')
            format.html { render :new }
            format.json { render json: @homepage_section.errors, status: :unprocessable_entity }
          end
        end
      end
      
      def edit
      end
      
      def show
      end
      
      def update
        respond_to do |format|
          if @homepage_section.update(homepage_section_params)
            flash[:success] = Spree.t('homepage_section.update_success')
            format.html { redirect_to admin_homepage_sections_path }
            format.json { render json: @homepage_section }
          else
            flash[:error] = @homepage_section.errors.full_messages.join(', ')
            format.html { render :edit }
            format.json { render json: @homepage_section.errors, status: :unprocessable_entity }
          end
        end
      end
      
      def destroy
        if @homepage_section.destroy
          flash[:success] = Spree.t('homepage_section.deleted_success')
        else
          flash[:error] = Spree.t('homepage_section.delete_failed')
        end
        redirect_to admin_homepage_sections_path
      end
      
      # Move section up in order
      def move_up
        @homepage_section = HomepageSection.find(params[:id])
        previous_section = HomepageSection.where('position < ?', @homepage_section.position)
                                          .ordered
                                          .last
        
        if previous_section
          ActiveRecord::Base.transaction do
            current_pos = @homepage_section.position
            prev_pos = previous_section.position
            
            @homepage_section.update_attribute(:position, prev_pos)
            previous_section.update_attribute(:position, current_pos)
          end
          flash[:success] = 'Section moved up successfully'
        else
          flash[:error] = 'Cannot move section up'
        end
        
        redirect_to admin_homepage_sections_path
      end
      
      # Move section down in order
      def move_down
        @homepage_section = HomepageSection.find(params[:id])
        next_section = HomepageSection.where('position > ?', @homepage_section.position)
                                      .ordered
                                      .first
        
        if next_section
          ActiveRecord::Base.transaction do
            current_pos = @homepage_section.position
            next_pos = next_section.position
            
            @homepage_section.update_attribute(:position, next_pos)
            next_section.update_attribute(:position, current_pos)
          end
          flash[:success] = 'Section moved down successfully'
        else
          flash[:error] = 'Cannot move section down'
        end
        
        redirect_to admin_homepage_sections_path
      end
      
      # Toggle visibility
      def toggle_visibility
        @homepage_section = HomepageSection.find(params[:id])
        @homepage_section.update(is_visible: !@homepage_section.is_visible)
        
        status = @homepage_section.is_visible ? 'visible' : 'hidden'
        flash[:success] = "Section is now #{status}"
        
        redirect_to admin_homepage_sections_path
      end
      
      private
      
      def set_homepage_section
        @homepage_section = HomepageSection.find(params[:id])
      end
      
      def homepage_section_params
        params.require(:homepage_section).permit(
          :title,
          :section_type,
          :content,
          :position,
          :is_visible,
          :settings
        )
      end
    end
  end
end
