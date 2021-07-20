module Spree
  module Admin
    class LiveStreamController < Spree::Admin::BaseController
      include Spree::FrontendHelper
      before_action :set_session
      def index
        collection(LiveStream)
        respond_with(@collection)
      end
      def new
        @live_stream = LiveStream.new
      end
      def edit
        @live_stream = LiveStream.find(params[:id])
      end
      def update
        @live_stream = LiveStream.find(params[:id])
        respond_to do |format|
          if @live_stream.update(live_stream_params)
            flash[:success] = Spree.t('live_stream.update_success')
            format.html { redirect_to admin_live_stream_index_path }
          else
            flash[:error] = @live_stream.errors.full_messages.join(', ')
            format.html { render :edit }
          end
        end
      end
      def show
        @live_stream = LiveStream.find(params[:id])
        require 'json'
        headers = {
          "Content-Type" => "application/json"
        }
        url = "https://api.mux.com/video/v1/live-streams/#{@live_stream.stream_id}"
        @response = RestClient::Request.new({
          method: :get,
          url: url,
          user: 'b49f3013-0715-47aa-84cb-315be5dc52bd',
          password: 'bmUuqEkhjHVKQr5xjMofA42y9EWKPy+YwesaTvikkY759n25brxn5evZZt+C/tu109A8DK4DmeR',
          headers: headers
          }).execute do |response, request, result|
            case response.code
            when 400
              [ :error, JSON.parse(response.to_str) ]
            when 200
              [ :success, JSON.parse(response.to_str) ]
            else
              [ :error, JSON.parse(response.to_str) ]
            end
          end
          if @response[0] == :success
            status = @response[1]['data']['status']
            playback_ids = @response[1]['data']['playback_ids'].pluck('id') if @response[1]['data']['playback_ids'].present?
            @live_stream.update(status: status, playback_ids: playback_ids)
            flash[:success] = Spree.t('live_stream.live_stream_show')
          else
            flash[:error] = Spree.t('live_stream.fail_to_execute_request', live_stream_real_time_error: @response[1]['error']['messages'].join(""))
            redirect_to admin_live_stream_index_path
          end
        end

        def create
          @live_stream = LiveStream.new(live_stream_params)
          require 'json'
          headers = {
            "Content-Type" => "application/json"
          }
          url = "https://api.mux.com/video/v1/live-streams"
          @response = RestClient::Request.new({
            method: :post,
            url: url,
            user: 'b49f3013-0715-47aa-84cb-315be5dc52bd',
            password: 'bmUuqEkhjHVKQr5xjMofA42y9EWKPy+YwesaTvikkY759n25brxn5evZZt+C/tu109A8DK4DmeR',
            body: { "playback_policy": "public", "new_asset_settings": { "playback_policy": "public" } },
            headers: headers
            }).execute do |response, request, result|
              case response.code
              when 400
                [ :error, JSON.parse(response.to_str) ]
              when 200
                [ :success, JSON.parse(response.to_str) ]
              when 201
                [ :success, JSON.parse(response.to_str) ]
              else
                [ :error, JSON.parse(response.to_str) ]
              end
            end
            if @response[0] == :success
              @live_stream.stream_key = @response[1]['data']['stream_key']
              @live_stream.stream_url = "rtmps://global-live.mux.com:443/app"
              @live_stream.stream_id = @response[1]['data']['id']
              @live_stream.playback_ids = @response[1]['data']['playback_ids'].pluck('id') if @response[1]['data']['playback_ids'].present?
              @live_stream.status = @response[1]['data']['status']
              respond_to do |format|
                if @live_stream.save
                  flash[:success] = Spree.t('live_stream.added_success')
                  format.html { redirect_to admin_live_stream_index_path }
                else
                  flash[:error] = @live_stream.errors.full_messages.join(', ')
                  format.html { render :new }
                end
              end
            else
              flash[:error] = Spree.t('live_stream.fail_to_execute_request', live_stream_real_time_error: @response[1]['error']['messages'].join(""))
              redirect_to new_admin_live_stream_path
            end
          end

          def destroy
            @live_stream = LiveStream.find(params[:id])
            require 'json'
            headers = {
              "Content-Type" => "application/json"
            }
            url = "https://api.mux.com/video/v1/live-streams/#{@live_stream.stream_id}"
            @response = RestClient::Request.new({
              method: :delete,
              url: url,
              user: 'b49f3013-0715-47aa-84cb-315be5dc52bd',
              password: 'bmUuqEkhjHVKQr5xjMofA42y9EWKPy+YwesaTvikkY759n25brxn5evZZt+C/tu109A8DK4DmeR',
              headers: headers
              }).execute do |response, request, result|
                case response.code
                when 400
                  [ :error, JSON.parse(response.to_str) ]
                when 204
                  [:success]
                else
                  [ :error, JSON.parse(response.to_str) ]
                end
              end
              if @response[0] == :success
                @live_stream.destroy
                flash[:success] = Spree.t('live_stream.live_stream_deleted')
                respond_with do |format|
                  format.html { redirect_to collection_url }
                  format.js  { render_js_for_destroy }
                end
              else
                flash[:error] = @response[1]['error']['messages'].join("")
                redirect_to admin_live_stream_index_path
              end
            end
            def generate_playback
              @live_stream = LiveStream.find(params[:id])
              require 'json'
              headers = {
                "Content-Type" => "application/json"
              }
              url = "https://api.mux.com/video/v1/live-streams/#{@live_stream.stream_id}/playback-ids"
              @response = RestClient::Request.new({
                method: :post,
                url: url,
                user: 'b49f3013-0715-47aa-84cb-315be5dc52bd',
                password: 'bmUuqEkhjHVKQr5xjMofA42y9EWKPy+YwesaTvikkY759n25brxn5evZZt+C/tu109A8DK4DmeR',
                payload: '{ "policy": "public" }',
                headers: headers
                }).execute do |response, request, result|
                  case response.code
                  when 400
                    [ :error, JSON.parse(response.to_str) ]
                  when 200
                    [ :success, JSON.parse(response.to_str) ]
                  when 201
                    [ :success, JSON.parse(response.to_str) ]
                  else
                    [ :error, JSON.parse(response.to_str) ]
                  end
                end
                if @response[0] == :success
                  flash[:success] = Spree.t('live_stream.playback_added')
                  respond_with do |format|
                    format.html { redirect_to admin_live_stream_path(id: @live_stream.id) }
                  end
                else
                  flash[:error] = @response[1]['error']['messages'].join("")
                  redirect_to admin_live_stream_path(id: @live_stream.id)
                end
              end
              private
              def set_session
                session[:return_to] = request.url
              end
              def live_stream_params
                params.require(:live_stream).permit(:title, :description, :stream_url, :stream_key, :stream_id, :playback_ids, :status, :start_date, :is_active, :product_ids => [])
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
