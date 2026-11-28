module Chat
  # The Rails admin inbox's snooze choices, in the chat's time zone (Chat.config.time_zone, from
  # CHAT_TIME_ZONE or the app's): an hour from now, tomorrow at 9:00 and next Monday at 9:00.
  module SnoozePresets
    MORNING_HOUR = 9
    LABELS = { '1h' => 'For 1 hour', 'tomorrow' => 'Until tomorrow, 9:00', 'monday' => 'Until next Monday, 9:00' }.freeze

    module_function

    # The time a preset snoozes until, or nil for an unknown preset.
    def until_time(preset, now: Time.current)
      local = now.in_time_zone(Chat.config.time_zone)
      case preset.to_s
      when '1h' then now + 1.hour
      when 'tomorrow' then (local + 1.day).change(hour: MORNING_HOUR)
      when 'monday' then local.next_week(:monday).change(hour: MORNING_HOUR)
      end
    end

    # [{ key, label, until }] for the snooze menu.
    def options(now: Time.current)
      LABELS.map { |key, label| { key: key, label: label, until: until_time(key, now: now).utc.iso8601 } }
    end
  end
end
