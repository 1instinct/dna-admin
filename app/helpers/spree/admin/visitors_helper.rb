module Spree
  module Admin
    # Small pieces of the Visitors pages: names, durations and ages from the adapter's ISO times.
    module VisitorsHelper
      def visitor_label(session)
        contact = session[:contact] || {}
        contact[:name].presence || contact[:email].presence || "Visitor ##{session[:id]}"
      end

      # "12 min" between two ISO times (or until now).
      def visitor_span(from_iso, to_iso = nil)
        from = parse_visitor_time(from_iso)
        return '' unless from

        to = parse_visitor_time(to_iso) || Time.current
        seconds = [(to - from).to_i, 0].max
        if seconds < 60 then "#{seconds} s"
        elsif seconds < 3600 then "#{seconds / 60} min"
        elsif seconds < 86_400 then "#{seconds / 3600} h #{(seconds % 3600) / 60} min"
        else "#{seconds / 86_400} d"
        end
      end

      def visitor_time(iso)
        time = parse_visitor_time(iso)
        time && l(time.in_time_zone, format: :short)
      end

      def visitor_utm(utm)
        return nil if utm.blank?

        utm.values_at(:source, :medium, :campaign).map(&:presence).compact.join(' / ')
      end

      def visitor_online_dot(online)
        content_tag(:span, '', class: "visitors__dot#{' is-online' if online}", 'aria-hidden': 'true') +
          content_tag(:span, online ? 'Online' : 'Offline', class: 'sr-only')
      end

      private

      def parse_visitor_time(iso)
        iso.present? ? Time.zone.parse(iso.to_s) : nil
      rescue ArgumentError
        nil
      end
    end
  end
end
