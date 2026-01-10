module Spree
  module Admin
    class HomepageSectionsController < Spree::Admin::BaseController
      before_action :set_homepage_section, only: [:edit, :update, :destroy, :show]
      
      def index
        @q = HomepageSection.ransack(params[:q])
        @collection = @q.result
                        .order(position: :asc)
                        .page(params[:page])
                        .per(params[:per_page] || 25)
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
                                          .order(position: :desc)
                                          .first
        
        if previous_section
          HomepageSection.transaction do
            temp_position = @homepage_section.position
            @homepage_section.update_column(:position, previous_section.position)
            previous_section.update_column(:position, temp_position)
          end
          flash[:success] = Spree.t('homepage_section.moved_up')
        end
        
        redirect_to admin_homepage_sections_path
      end
      
      # Move section down in order
      def move_down
        @homepage_section = HomepageSection.find(params[:id])
        next_section = HomepageSection.where('position > ?', @homepage_section.position)
                                      .order(position: :asc)
                                      .first
        
        if next_section
          HomepageSection.transaction do
            temp_position = @homepage_section.position
            @homepage_section.update_column(:position, next_section.position)
            next_section.update_column(:position, temp_position)
          end
          flash[:success] = Spree.t('homepage_section.moved_down')
        end
        
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
