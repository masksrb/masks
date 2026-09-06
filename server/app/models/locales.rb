module Locales
  LONGEST = 512
  TAG = /\A[a-z]{1,8}(?:-[a-z0-9]{1,8})*\z/
  QUALITY = /\Aq=(\d(?:\.\d{1,3})?)\z/i

  class << self
    def available
      I18n.available_locales
    end

    def negotiate(header)
      requested(header).lazy.filter_map { |tag| match(tag) }.first || I18n.default_locale
    end

    def tag(locale = I18n.locale)
      locale.to_s.tr("_", "-")
    end

    private

      def requested(header)
        header.to_s[0, LONGEST].split(",").filter_map { |entry| weighed(entry) }
              .sort_by { |_, weight| -weight }
              .map(&:first)
      end

      def weighed(entry)
        tag, *parameters = entry.split(";").map { |part| part.strip.downcase }
        return nil unless tag&.match?(TAG)

        given = parameters.filter_map { |parameter| parameter[QUALITY, 1] }.first
        weight = given ? Float(given, exception: false) : 1.0
        return nil if weight.nil? || weight <= 0

        [ tag, weight ]
      end

      def match(tag)
        exact = available.find { |locale| self.tag(locale).downcase == tag }
        return exact if exact

        language = tag.split("-").first

        available.find { |locale| self.tag(locale).downcase.split("-").first == language }
      end
  end
end
