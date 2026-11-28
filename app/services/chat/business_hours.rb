module Chat
  # "1-5 09:00-17:00" style opening hours for the widget's online flag.
  module BusinessHours
    module_function

    FORMAT = /\A\s*([1-7])(?:\s*-\s*([1-7]))?\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*\z/.freeze

    def parse(value)
      match = FORMAT.match(value.to_s)
      return unless match

      first = match[1].to_i
      last = (match[2] || match[1]).to_i
      days = first <= last ? (first..last).to_a : (first..7).to_a + (1..last).to_a
      { days: days, from: match[3], to: match[4] }
    end

    def open?(hours, time)
      return false unless hours.is_a?(Hash) && hours[:days].present?
      return false unless Array(hours[:days]).map(&:to_i).include?(time.to_date.cwday)

      minutes = (time.hour * 60) + time.min
      from = to_minutes(hours[:from])
      to = to_minutes(hours[:to])
      return false unless from && to

      from <= to ? minutes >= from && minutes < to : minutes >= from || minutes < to
    end

    def to_minutes(text)
      hours, minutes = text.to_s.split(':').map(&:to_i)
      return unless hours && minutes && hours.between?(0, 24) && minutes.between?(0, 59)

      (hours * 60) + minutes
    end
  end
end
