module Spree
  module Api
    module V1
      class FavoritesController < Spree::Api::BaseController
        include Swagger::Blocks
        include Response
        before_action :authenticate_user
        before_action :load_variant, only: [:toggle]
        before_action :load_favorite, only: [:destroy]

        swagger_path '/favorites' do
          operation :get do
            key :summary, 'LIST USER FAVORITES'
            key :description, 'Get all favorites for the authenticated user'
            key :tags, ['Favorites']
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (spree_api_key)'
              key :required, true
              key :type, :string
            end
            
            parameter do
              key :name, 'page'
              key :in, :query
              key :description, 'Page number for pagination'
              key :required, false
              key :type, :integer
            end
            
            parameter do
              key :name, 'per_page'
              key :in, :query
              key :description, 'Items per page (default: 25)'
              key :required, false
              key :type, :integer
            end
            
            response 200 do
              key :description, 'Successful'
              schema do
                key :'$ref', :favorites_list_response
              end
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
          end
        end

        swagger_path '/favorites/toggle' do
          operation :post do
            key :summary, 'TOGGLE FAVORITE'
            key :description, 'Add or remove a variant from favorites'
            key :tags, ['Favorites']
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (spree_api_key)'
              key :required, true
              key :type, :string
            end
            
            parameter do
              key :name, 'variant_id'
              key :in, :formData
              key :description, 'Variant ID to favorite/unfavorite'
              key :required, true
              key :type, :integer
            end
            
            response 200 do
              key :description, 'Successful'
              schema do
                key :'$ref', :favorite_toggle_response
              end
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
            
            response 404 do
              key :description, 'Variant not found'
            end
          end
        end

        swagger_path '/favorites/{id}' do
          operation :delete do
            key :summary, 'REMOVE FAVORITE'
            key :description, 'Remove a specific favorite by ID'
            key :tags, ['Favorites']
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (spree_api_key)'
              key :required, true
              key :type, :string
            end
            
            parameter do
              key :name, 'id'
              key :in, :path
              key :description, 'Favorite ID to remove'
              key :required, true
              key :type, :integer
            end
            
            response 200 do
              key :description, 'Successful'
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
            
            response 404 do
              key :description, 'Favorite not found'
            end
          end
        end

        # GET /api/v1/favorites
        def index
          @favorites = current_api_user.favorites
                                   .includes(variant: [:product, :images, :prices])
                                   .recent
                                   .page(params[:page])
                                   .per(params[:per_page] || 25)
          
          render_favorites_success(@favorites)
        end

        # POST /api/v1/favorites/toggle
        def toggle
          is_favorited = Favorite.toggle(current_api_user, @variant)
          
          if is_favorited
            success_model(200, "Added to favorites")
          else
            success_model(200, "Removed from favorites")
          end
        end

        # DELETE /api/v1/favorites/:id
        def destroy
          if @favorite.destroy
            success_model(200, "Favorite removed successfully")
          else
            error_model(422, "Could not remove favorite")
          end
        end

        # GET /api/v1/favorites/check
        def check
          variant = Spree::Variant.find_by(id: params[:variant_id])
          return error_model(404, "Variant not found") unless variant
          
          is_favorited = Favorite.favorited?(current_api_user, variant)
          
          render json: {
            status: 200,
            message: "Success",
            is_favorited: is_favorited
          }
        end

        private

        def load_variant
          @variant = Spree::Variant.find_by(id: params[:variant_id])
          return error_model(404, "Variant not found") unless @variant
        end

        def load_favorite
          @favorite = current_api_user.favorites.find_by(id: params[:id])
          return error_model(404, "Favorite not found") unless @favorite
        end

        def render_favorites_success(favorites)
          favorites_data = favorites.map do |favorite|
            variant = favorite.variant
            product = variant.product
            
            {
              id: favorite.id,
              created_at: favorite.created_at,
              is_public: favorite.is_public || false,
              variant: {
                id: variant.id,
                sku: variant.sku,
                name: variant.name,
                price: variant.price.to_s,
                in_stock: variant.in_stock?,
                product: {
                  id: product.id,
                  name: product.name,
                  slug: product.slug,
                  description: product.description,
                  images: product.images.map { |img| { url: img.attachment.url } }
                }
              }
            }
          end
          
          render json: {
            status: 200,
            message: "Favorites retrieved successfully",
            data: favorites_data,
            meta: {
              total_count: favorites.total_count,
              current_page: favorites.current_page,
              total_pages: favorites.total_pages,
              per_page: favorites.limit_value
            }
          }
        end
        
        swagger_path '/favorites/{id}/toggle_public' do
          operation :post do
            key :summary, 'TOGGLE FAVORITE PUBLIC/PRIVATE'
            key :description, 'Toggle whether a favorite is public or private'
            key :tags, ['Favorites']
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (spree_api_key)'
              key :required, true
              key :type, :string
            end
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'Favorite ID'
              key :required, true
              key :type, :integer
            end
            
            response 200 do
              key :description, 'Successfully toggled'
              schema do
                key :'$ref', :favorite_toggle_public_response
              end
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
            
            response 404 do
              key :description, 'Favorite not found'
            end
          end
        end
        
        swagger_schema :favorite_toggle_public_response do
          property :status do
            key :type, :integer
          end
          property :message do
            key :type, :string
          end
          property :data do
            property :id do
              key :type, :integer
            end
            property :is_public do
              key :type, :boolean
            end
          end
        end
        
        def toggle_public
          favorite = current_api_user.favorites.find_by(id: params[:id])
          unless favorite
            return error_model(404, "Favorite not found")
          end
          
          favorite.update(is_public: !favorite.is_public)
          
          render json: {
            status: 200,
            message: favorite.is_public ? "Favorite is now public" : "Favorite is now private",
            data: {
              id: favorite.id,
              is_public: favorite.is_public
            }
          }
        end
      end
    end
  end
end
