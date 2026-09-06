require "test_helper"

class LocalesTest < ActiveSupport::TestCase
  test "a browser that asks for nothing is answered in the default" do
    assert_equal I18n.default_locale, Locales.negotiate(nil)
    assert_equal I18n.default_locale, Locales.negotiate("")
  end

  test "a language masks does not speak falls back rather than raising" do
    assert_equal I18n.default_locale, Locales.negotiate("de-AT,de;q=0.9")
  end

  test "quality decides the order, not the order in the header" do
    with_locales(%i[en fr]) do
      assert_equal :fr, Locales.negotiate("en;q=0.2, fr;q=0.9")
      assert_equal :en, Locales.negotiate("fr;q=0.3, en;q=0.8")
    end
  end

  test "a region falls back to its language" do
    with_locales(%i[en fr]) do
      assert_equal :fr, Locales.negotiate("fr-CA")
    end
  end

  test "an entry refused outright is not offered" do
    with_locales(%i[en fr]) do
      assert_equal :en, Locales.negotiate("fr;q=0, en")
    end
  end

  test "a header is a header, not a lookup key" do
    with_locales(%i[en fr]) do
      [
        "../../../etc/passwd",
        "en\r\nX-Injected: yes",
        "#{'a' * 4096},fr",
        "*",
        ";;;",
        "en_US"
      ].each do |header|
        assert_includes I18n.available_locales, Locales.negotiate(header),
                        "#{header.inspect} negotiated something masks does not speak"
      end
    end
  end

  test "a tag is the form a Content-Language header and an html lang want" do
    assert_equal "en", Locales.tag(:en)
    assert_equal "pt-BR", Locales.tag(:"pt_BR")
  end

  private

    def with_locales(locales)
      held = I18n.available_locales
      I18n.available_locales = locales
      yield
    ensure
      I18n.available_locales = held
    end
end
