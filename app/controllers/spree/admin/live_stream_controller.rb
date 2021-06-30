module Spree
  module Admin
    class LiveStreamController < Spree::Admin::BaseController
      before_action :set_session
      def index
        # require 'json'
        # headers = {
        #   "Content-Type" => "application/json"
        # }
        # url = 'https://api.mux.com/video/v1/live-streams'
        # @response = RestClient::Request.new({
        #   method: :get,
        #   url: url,
        #   user: 'b49f3013-0715-47aa-84cb-315be5dc52bd',
        #   password: 'bmUuqEkhjHVKQr5xjMofA42y9EWKPy+YwesaTvikkY759n25brxn5evZZt+C/tu109A8DK4DmeR',
        #   headers: headers
        # }).execute do |response, request, result|
        #   case response.code
        #   when 400
        #     [ :error, JSON.parse(response.to_str) ]
        #   when 200
        #     [ :success, JSON.parse(response.to_str) ]
        #   else
        #     fail "Invalid response #{response.to_str} received."
        #   end
        # end
        # if @response[0] == :success
        #   live_streams = []
        #   @response[1].each do |data|
        #     puts "**********************#{data}"
        #   end
        # else
        #
        # end
        @live_streams = LiveStream.all
      end
      def new
        @live_stream = LiveStream.new
      end
      def edit
        @live_stream = LiveStream.find(params[:id])
      end
      def update
        @live_stream = LiveStream.find(params[:id])
        if @live_stream.update(live_stream_params)
          flash[:notice] = 'Live Stream updated successfully.'
          redirect_to admin_live_stream_index_path
        else
          flash[:error] = @live_stream.errors.join("")
          redirect_to admin_live_stream_index_path
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
              fail "Invalid response #{response.to_str} received."
            end
          end
          if @response[0] == :success
            status = @response[1]['data']['status']
            playback_ids = @response[1]['data']['playback_ids'].pluck('id') if @response[1]['data']['playback_ids'].present?
            puts "*****************************#{playback_ids}"

            @live_stream.update(status: status, playback_ids: playback_ids)

            flash[:success] = Spree.t('live_stream.live_stream_show')
          else
            flash[:error] = @response[1]['error']['messages'].join("")
            redirect_to admin_live_stream_index_path
          end
      end

      def create
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
              fail "Invalid response #{response.to_str} received."
            end
          end
          if @response[0] == :success
            @live_stream = LiveStream.new(live_stream_params)
            @live_stream.stream_key = @response[1]['data']['stream_key']
            @live_stream.stream_url = "rtmps://global-live.mux.com:443/app"
            @live_stream.stream_id = @response[1]['data']['id']
            @live_stream.playback_ids = @response[1]['data']['playback_ids'].pluck('id') if @response[1]['data']['playback_ids'].present?
            @live_stream.status = @response[1]['data']['status']
            if @live_stream.save
              flash[:notice] = 'Live Stream Added successfully.'
              redirect_to admin_live_stream_index_path
            else
              flash[:error] = @response[1]['error']['messages'].join("")
              redirect_to admin_live_stream_index_path
            end
          else
            flash[:error] = @response[1]
            redirect_to admin_live_stream_index_path
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
                fail "Invalid response #{response.to_str} received."
                redirect_to admin_live_stream_index_path
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
                fail "Invalid response #{response.to_str} received."
              end
            end
            if @response[0] == :success
              flash[:success] = Spree.t('live_stream.playback_added')
              respond_with do |format|
                format.html { redirect_to admin_live_stream_path(id: @live_stream.id) }
              end
            else
              flash[:error] = @response[1]['error']['messages'].join("")
              redirect_to admin_live_stream_path
            end
        end
        private
        def set_session
          session[:return_to] = request.url
        end
        def live_stream_params
          params.require(:live_stream).permit(:title, :description, :stream_url, :stream_key, :stream_id, :playback_ids, :status, :start_date, :is_active)
        end
      end
    end
  end
