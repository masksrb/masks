require_relative "test_helper"

class RefreshTest < EngineIntegrationTest
  def json_headers
    host.merge("HTTP_ACCEPT" => "application/json")
  end

  test "two processes holding one expired session refresh it once and keep the same tokens" do
    sign_in!
    other = open_session
    cookies.to_hash.each { |name, value| other.cookies[name] = value }

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_response :success

      other.get "/auth/session", headers: json_headers

      assert_equal 200, other.response.status
    end

    assert_equal 1, issuer.refreshes.size
    assert held_session(other)["access_token"].present?
    assert_equal held_session["access_token"], held_session(other)["access_token"]
    assert_equal held_session["refresh_token"], held_session(other)["refresh_token"]
  end

  test "a refresh masks cannot answer keeps the session, so a later request tries again" do
    sign_in!
    issuer.refresh_outage = true

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_response :unauthorized
      assert held_session.present?

      issuer.refresh_outage = false

      get "/auth/session", headers: json_headers

      assert_response :success
    end

    assert_equal 2, issuer.refreshes.size
  end

  test "a refreshed session keeps when it signed in, so a later logout still reaches it" do
    sign_in!
    signed_in_at = held_session["signed_in_at"]

    assert_kind_of Integer, signed_in_at

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_equal signed_in_at, held_session["signed_in_at"]
    end
  end
end
