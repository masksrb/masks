module Masks
  module Server
    require "test_helper"

    class LanguageTest < ActionDispatch::IntegrationTest
      setup { host! host_for(@tenant) }

      test "the sign-in page answers in the language the browser asks for" do
        { "de-DE,de;q=0.9" => "de", "fr-FR" => "fr", "es" => "es", "it" => "en" }.each do |asked, locale|
          get "/login", headers: { "Accept-Language" => asked }

          assert_match %(lang="#{locale}"), response.body
          assert_match ERB::Util.html_escape(I18n.t("logins.signing_up.setup_title", locale: locale)), response.body
        end
      end

      test "an expired link says so in the visitor's language" do
        get "/verify/not-a-token", headers: { "Accept-Language" => "de" }

        assert_response :gone
        assert_match "Dieser Bestätigungslink ist nicht mehr gültig", response.body
      end

      test "an app's ui_locales outweighs the browser for the rest of that sign-in" do
        get "/login", params: { ui_locales: "es fr" }, headers: { "Accept-Language" => "de" }
        assert_match %(lang="es"), response.body

        get "/login", headers: { "Accept-Language" => "de" }
        assert_match %(lang="es"), response.body
      end

      test "a ui_locales masks does not speak leaves the browser's choice" do
        get "/login", params: { ui_locales: "it ja" }, headers: { "Accept-Language" => "fr" }

        assert_match %(lang="fr"), response.body
      end
    end
  end
end
