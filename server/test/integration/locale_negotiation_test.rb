require "test_helper"

class LocaleNegotiationTest < ActionDispatch::IntegrationTest
  test "a page says which language it came back in, and that the language was a choice" do
    host! host_for(@tenant)

    get "/login", headers: { "Accept-Language" => "en-GB,en;q=0.9" }

    assert_response :success
    assert_equal "en", response.headers["Content-Language"]
    assert_includes response.headers["Vary"].to_s, "Accept-Language"
    assert_match %r{<html lang="en"}, response.body
  end

  test "the header is negotiated, not trusted" do
    host! host_for(@tenant)

    get "/login", headers: { "Accept-Language" => "de-DE,de;q=0.9,tr;q=0.8" }

    assert_response :success
    assert_equal "en", response.headers["Content-Language"]
  end

  test "the browser is handed the same copy the server rendered from" do
    host! host_for(@tenant)

    get "/login"

    copy = auth_data["copy"]

    assert_equal I18n.t("logins.setup.submit"), copy["submit"]
    assert_equal I18n.t("logins.shared.continue"), copy["continue"]
    assert_match CGI.escapeHTML(copy["note"]), response.body
  end

  test "a prompt ships the strings its own screen needs and no others" do
    actor = create_actor(@tenant, nickname: "owner", password: "a-long-enough-password")
    host! host_for(@tenant)

    post "/login", params: { event: "identify", identifier: actor.nickname }, as: :json

    copy = JSON.parse(response.body)["copy"]

    assert_equal I18n.t("logins.first_factor.title"), copy["title"]
    assert_nil copy["token_hint"]
  end

  test "every string a prompt renders exists in the default locale" do
    I18n.t("logins").each do |prompt, strings|
      next unless strings.is_a?(Hash)

      strings.each do |key, value|
        assert_kind_of String, value, "logins.#{prompt}.#{key} is not a string"
        assert value.present?, "logins.#{prompt}.#{key} is blank"
      end
    end
  end

  test "the issuer says which languages it can prompt in" do
    assert_equal I18n.available_locales.map { |locale| Locales.tag(locale) },
                 issuer_for(@tenant).discovery["ui_locales_supported"]
  end

  test "the manage scope is published in every language masks speaks" do
    published = issuer_for(@tenant).protected_resource

    assert_equal({ Scopes::MANAGE => I18n.t("scopes.manage") }, published["scope_descriptions"])

    I18n.available_locales.each do |locale|
      assert_equal({ Scopes::MANAGE => I18n.t("scopes.manage", locale: locale) },
                   published["scope_descriptions##{Locales.tag(locale)}"])
    end
  end
end
