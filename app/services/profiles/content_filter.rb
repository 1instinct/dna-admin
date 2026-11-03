module Profiles
  # Blocked-terms filter (Profiles.config.blocked_terms).
  #
  #   mode: :handle  a term anywhere in the handle, underscores ignored ("bad_word" hits "badword")
  #   mode: :words   a term as a whole word (or the word plus "s"); multi-word terms as a phrase
  module ContentFilter
    module_function

    def allowed?(text, mode:)
      return true if text.blank?

      terms = Profiles.config.blocked_terms
      case mode
      when :handle
        compact = squash(text)
        terms.none? { |term| (t = squash(term)).present? && compact.include?(t) }
      when :words
        words = tokens(text)
        phrase = " #{words.join(' ')} "
        terms.none? do |term|
          parts = tokens(term)
          next false if parts.empty?

          if parts.size == 1
            words.include?(parts.first) || words.include?("#{parts.first}s")
          else
            phrase.include?(" #{parts.join(' ')} ")
          end
        end
      else
        raise ArgumentError, "unknown mode #{mode.inspect}"
      end
    end

    def squash(text)
      text.to_s.downcase.gsub(/[^a-z0-9]/, '')
    end

    def tokens(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/)
    end
  end
end
