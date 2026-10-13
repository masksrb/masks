require_relative "test_helper"

class SessionCookiesTest < EngineIntegrationTest
  RAILS_SESSION = "_masks_rails_test".freeze

  def json_headers
    host.merge("HTTP_ACCEPT" => "application/json")
  end

  def masks_cookies
    Array(response.headers["Set-Cookie"]).flat_map { |held| held.split("\n") }.select { |held| held.start_with?("masks") }
  end

  test "a session with a large access token is split across several cookies and still signs in" do
    issuer.padding = 9000

    sign_in!

    assert_redirected_to "/"
    assert_operator masks_cookies.size, :>, 1
    masks_cookies.each { |held| assert_operator held.bytesize, :<, 4096 }
    assert_operator cookies[RAILS_SESSION].bytesize, :<, 1024, "the Rails session holds no tokens"

    get "/auth/session", headers: json_headers

    assert_response :success
    assert_operator held_session["access_token"].bytesize, :>, 9000
  end

  test "a session that shrinks drops the cookies it no longer needs" do
    issuer.padding = 9000
    sign_in!

    assert_not_nil cookies["masks-1"]

    issuer.padding = 0

    travel 2.hours do
      get "/auth/session", headers: json_headers
    end

    assert_response :success
    assert cookies["masks-1"].blank?
  end

  test "each cookie is HttpOnly and SameSite=Lax" do
    sign_in!

    assert_not_empty masks_cookies
    masks_cookies.each do |held|
      assert_match(/httponly/i, held)
      assert_match(/samesite=lax/i, held)
      assert_match(%r{path=/(;|\z)}i, held)
    end
  end

  test "an app that resets its session signs the person out of masks too" do
    sign_in!
    cookies.delete(RAILS_SESSION)

    get "/auth/session", headers: json_headers

    assert_response :unauthorized
    assert cookies["masks"].blank?
  end

  test "masks cookies carried to another browser do not sign it in" do
    sign_in!
    other = open_session
    other.cookies["masks"] = cookies["masks"]

    other.get "/auth/session", headers: json_headers

    assert_equal 401, other.response.status
  end

  test "a cookie that was changed is refused" do
    sign_in!
    value = cookies["masks"]
    cookies["masks"] = value.sub(/.\z/) { |last| last == "A" ? "B" : "A" }

    get "/auth/session", headers: json_headers

    assert_response :unauthorized
  end

  test "a session too large for every cookie refuses the sign-in instead of failing" do
    issuer.padding = 40_000

    sign_in!

    assert_response :bad_request
    assert_match "more than 8 cookies can hold", response.body
  end

  test "over https the cookies take the __Host- prefix and the Secure flag" do
    https!
    sign_in!

    hosted = Array(response.headers["Set-Cookie"]).flat_map { |held| held.split("\n") }.grep(/\A__Host-masks=/)

    assert_not_empty hosted
    hosted.each { |held| assert_match(/secure/i, held) }

    get "/auth/session", headers: json_headers

    assert_response :success
  end
end
