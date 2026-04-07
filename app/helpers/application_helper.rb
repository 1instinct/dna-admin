module ApplicationHelper

	def screentime datetime, timezone=nil
		if datetime.nil?
			return datetime
		end
		if timezone
			datetime = datetime.in_time_zone(timezone)
		end
		make_datetime_s(datetime)
	end


    def make_datetime_s datetime
        if datetime.respond_to? :to_formatted_s
            datetime.to_formatted_s(:date_and_time)
        end
    end

end
