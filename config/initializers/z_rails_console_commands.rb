#######
#### THIS initializer MUST BE LAST


# if defined?(Rails::Console)
	# this runs only in rails console

	# C = Chat
	# P = Pusher
	# U = User
	# W = Websocket


	class Object

	    def mets
	        (self.methods - Object.methods).sort_by { |m| m }
	    end

	    def ih(hash)
	        hash.with_indifferent_access
	    end

	    def stoplight meta=nil
	        if meta == :help
	            return { meta: [], modes: [:stop, :support, :live]}
	        end
	        :live
	    end

	    def sl meta=nil
	        stoplight meta
	    end
	end

# end

