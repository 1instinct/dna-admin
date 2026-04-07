# app/controllers/hello_world_controller.rb

!!!!!  Use :ptest in rails console !!!!!


class HelloWorldController < ApplicationController
    def hello_world
        Pusher.trigger('my-channel', 'my-event', { message: 'it works!!' })
    end
end
