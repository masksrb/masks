module Masks
  module Server
    require "test_helper"

    class TranslationsTest < ActiveSupport::TestCase
      ROOT = Engine.root.join("config/locales")
      PLACEHOLDER = /%\{\w+\}/

      def flat(hash, prefix = nil)
        hash.flat_map do |key, value|
          path = [ prefix, key ].compact.join(".")
          value.is_a?(Hash) ? flat(value, path) : [ [ path, value ] ]
        end
      end

      def held(locale)
        ROOT.glob("#{locale}/**/*.yml").each_with_object({}) do |file, keys|
          keys.merge!(flat(YAML.load_file(file).fetch(locale.to_s)).to_h)
        end
      end

      def others
        ROOT.children.select(&:directory?).map { |dir| dir.basename.to_s } - [ "en" ]
      end

      test "masks ships French, Spanish, and German" do
        assert_equal %w[de en es fr], ROOT.children.select(&:directory?).map { |dir| dir.basename.to_s }.sort
      end

      test "every language says everything English does, with the same placeholders" do
        english = held(:en)

        others.each do |locale|
          translated = held(locale)

          assert_empty english.keys - translated.keys, "#{locale} is missing keys"
          assert_empty translated.keys - english.keys, "#{locale} has keys English does not"

          differing = english.select do |key, value|
            value.is_a?(String) && translated[key].is_a?(String) &&
              value.scan(PLACEHOLDER).sort != translated[key].scan(PLACEHOLDER).sort
          end

          assert_empty differing.keys, "#{locale} changes placeholders"
        end
      end

      ALLOWLIST = YAML.load_file(File.expand_path("translations_allowlist.yml", __dir__))
      TRANSLATED_BAR = 98.0

      def allowed?(locale, value)
        return true if value.gsub(PLACEHOLDER, "").gsub(/[[:punct:][:space:]]/, "").empty?

        ALLOWLIST.fetch("everywhere").include?(value) || ALLOWLIST.fetch(locale, []).include?(value)
      end

      test "at least 98 percent of each language differs from English, allowing the words that are the same everywhere" do
        english = held(:en).select { |_, value| value.is_a?(String) && value.strip.present? }

        others.each do |locale|
          translated = held(locale)
          untranslated = english.select { |key, value| translated[key] == value && !allowed?(locale, value) }
          share = 100.0 * (english.size - untranslated.size) / english.size

          puts format("%<locale>s: %<share>.2f%% translated, %<left>d still English", locale: locale, share: share, left: untranslated.size)
          untranslated.each { |key, value| puts "  #{key} = #{value.inspect}" }

          assert_operator share, :>=, TRANSLATED_BAR, "#{locale} is #{share.round(2)}% translated; #{untranslated.size} values are still English"
        end
      end

      test "a dated string reads in the visitor's language" do
        I18n.with_locale(:fr) { assert_match "janvier", I18n.l(Date.new(2026, 1, 5), format: :long) }
        I18n.with_locale(:de) { assert_match "Januar", I18n.l(Date.new(2026, 1, 5), format: :long) }
      end
    end
  end
end
