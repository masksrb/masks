module Localized
  SUFFIX = "#".freeze

  class << self
    def field(document, name, locale: I18n.locale)
      return nil unless document.is_a?(Hash)

      tagged = tags(document, name)

      preferred(locale).lazy.filter_map { |tag| tagged[tag] }.first || tagged[nil]
    end

    def fields(document, name, locale: I18n.locale)
      return {} unless document.is_a?(Hash)

      tagged = tags(document, name)
      untagged = tagged.delete(nil)

      preferred(locale).reverse.reduce(hash(untagged)) do |held, tag|
        held.merge(hash(tagged[tag]))
      end
    end

    private

      def tags(document, name)
        document.each_with_object({}) do |(key, value), held|
          field, tag = key.to_s.split(SUFFIX, 2)
          next unless field == name

          held[tag&.downcase] = value
        end
      end

      def preferred(locale)
        tag = Locales.tag(locale).downcase
        language = tag.split("-").first

        [ tag, language ].uniq
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end
  end
end
