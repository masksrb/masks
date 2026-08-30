require "test_helper"

class LoginsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor
    host! host_for(@tenant)
  end

  def event(name, **updates)
    post "/login", params: { event: name, **updates }, as: :json
    JSON.parse(response.body)
  end

  test "the page seeds the client with the opening prompt" do
    get "/login"

    assert_response :success
    assert_match "identify", response.body
  end

  test "an unknown hostname serves no tenant" do
    host! "nobody.auth.test"
    get "/login"

    assert_response :not_found
  end

  test "the flow advances through identify and password" do
    assert_equal "identify", event("identify", identifier: "")["prompt"]
    assert_equal "first-factor", event("identify", identifier: "owner")["prompt"]

    wrong = event("password", password: "nope")
    assert_equal "first-factor", wrong["prompt"]
    assert_includes wrong["warnings"], "invalid-credentials"

    settled = event("password", password: "password")
    assert_equal "settled", settled["prompt"]
    assert settled["settled"]
    assert_equal "/", settled["redirectTo"]
  end

  test "settling signs the actor in" do
    event("identify", identifier: "owner")
    event("password", password: "password")

    get "/"
    assert_match @actor.nickname, response.body
  end

  test "the login store does not survive signing in" do
    event("identify", identifier: "owner")
    event("password", password: "password")

    assert_nil session["login"]
  end

  test "starting over clears the flow" do
    event("identify", identifier: "owner")

    delete "/login", as: :json

    assert_equal "identify", JSON.parse(response.body)["prompt"]
  end

  test "a second factor is required before the actor is signed in" do
    enable_otp(@actor)

    event("identify", identifier: "owner")
    assert_equal "second-factor", event("password", password: "password")["prompt"]

    get "/"
    assert_no_match @actor.nickname, response.body
  end

  test "a valid code completes a second-factor sign-in" do
    totp = enable_otp(@actor)

    event("identify", identifier: "owner")
    event("password", password: "password")

    assert_equal "settled", event("otp", code: totp.now)["prompt"]

    get "/"
    assert_match @actor.nickname, response.body
  end

  test "the response never names an actor before the first factor passes" do
    body = event("identify", identifier: "owner")

    assert_nil body["actor"]
  end

  test "one tenant's actor cannot sign in against another" do
    create_actor(@other, nickname: "theirs", password: "another-password")
    host! host_for(@other)

    event("identify", identifier: "owner")
    body = event("password", password: "password")

    assert_equal "first-factor", body["prompt"]
    assert_includes body["warnings"], "invalid-credentials"
  end
end
