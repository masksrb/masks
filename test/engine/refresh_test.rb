require_relative "test_helper"

class RefreshTest < EngineIntegrationTest
  COOKIE = "_masks_rails_test".freeze

  def json_headers
    host.merge("HTTP_ACCEPT" => "application/json")
  end

  test "two processes holding one expired session refresh it once and keep the same tokens" do
    sign_in!
    held = cookies[COOKIE]
    other = open_session
    other.cookies[COOKIE] = held

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_response :success

      other.get "/auth/session", headers: json_headers

      assert_equal 200, other.response.status
    end

    assert_equal 1, issuer.refreshes.size
    assert_equal request.session["masks"]["access_token"], other.request.session["masks"]["access_token"]
    assert_equal request.session["masks"]["refresh_token"], other.request.session["masks"]["refresh_token"]
  end

  test "a refresh masks cannot answer keeps the session, so a later request tries again" do
    sign_in!
    issuer.refresh_outage = true

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_response :unauthorized
      assert request.session["masks"].present?

      issuer.refresh_outage = false

      get "/auth/session", headers: json_headers

      assert_response :success
    end

    assert_equal 2, issuer.refreshes.size
  end

  test "a refreshed session keeps when it signed in, so a later logout still reaches it" do
    sign_in!
    signed_in_at = request.session["masks"]["signed_in_at"]

    assert_kind_of Integer, signed_in_at

    travel 2.hours do
      get "/auth/session", headers: json_headers

      assert_equal signed_in_at, request.session["masks"]["signed_in_at"]
    end
  end
end
