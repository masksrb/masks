require "test_helper"

class PushedAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  def push(**params)
    post "/par", params: {
      response_type: "code",
      client_id: @registration["client_id"],
      client_secret: @registration["client_secret"],
      redirect_uri: OidcFlow::REDIRECT_URI,
      scope: "openid profile email",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }.merge(params).compact

    JSON.parse(response.body)
  end

  def visit(request_uri, client_id: @registration["client_id"], **params)
    get "/authorize?#{URI.encode_www_form({ client_id: client_id, request_uri: request_uri }.merge(params))}"
    response
  end

  test "a pushed request answers with a request_uri that expires" do
    body = push

    assert_response :created
    assert body["request_uri"].start_with?(PushedRequest::PREFIX)
    assert_operator body["expires_in"], :>, 0
    assert_operator body["expires_in"], :<=, 90
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "the request the browser carries is the one that was pushed" do
    request_uri = push(state: "opaque", nonce: "n-once")["request_uri"]

    sign_in_as(@actor)
    visit(request_uri)
    consent!

    assert redirected["code"].present?
    assert_equal "opaque", redirected["state"]

    body = token(
      grant_type: "authorization_code", code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"]
    )

    assert_equal "n-once", claims_in(body["id_token"])["nonce"]
  end

  test "nothing the browser adds to the query survives the pushed request" do
    request_uri = push(state: "pushed", scope: "openid")["request_uri"]

    sign_in_as(@actor)
    visit(request_uri, state: "tampered", scope: "openid profile email", redirect_uri: "https://evil.example.com/cb")
    consent!

    assert_equal "pushed", redirected["state"]
    assert redirected["code"].present?
    assert response.location.start_with?(OidcFlow::REDIRECT_URI)
  end

  test "a request_uri is spent the first time it is followed" do
    request_uri = push["request_uri"]

    sign_in_as(@actor)
    visit(request_uri)
    consent!

    assert redirected["code"].present?

    visit(request_uri)

    assert_response :bad_request
    assert_match "invalid_request_uri", response.body
  end

  test "a request_uri that has expired is refused" do
    request_uri = push["request_uri"]

    travel 2.minutes do
      sign_in_as(@actor)
      visit(request_uri)

      assert_response :bad_request
      assert_match "invalid_request_uri", response.body
    end
  end

  test "a request_uri belongs to the client that pushed it" do
    request_uri = push["request_uri"]
    other = register(client_name: "Other")

    sign_in_as(@actor)
    visit(request_uri, client_id: other["client_id"])

    assert_response :bad_request
    assert_match "invalid_request_uri", response.body
  end

  test "a request_uri this server never issued is not a request_uri it supports" do
    sign_in_as(@actor)
    visit("https://evil.example.com/request.jwt")

    assert_response :bad_request
    assert_match "request_uri_not_supported", response.body
  end

  test "a pushed request is refused without the client that claims it" do
    post "/par", params: {
      response_type: "code",
      client_id: @registration["client_id"],
      client_secret: "wrong",
      redirect_uri: OidcFlow::REDIRECT_URI,
      scope: "openid"
    }

    assert_response :unauthorized
    assert_equal "invalid_client", JSON.parse(response.body)["error"]
  end

  test "a client that authenticates in the header need not repeat its id in the body" do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(
      @registration["client_id"], @registration["client_secret"]
    )

    post "/par",
         params: {
           response_type: "code", redirect_uri: OidcFlow::REDIRECT_URI,
           scope: "openid profile email",
           code_challenge: challenge, code_challenge_method: "S256"
         },
         headers: { "HTTP_AUTHORIZATION" => credentials }

    assert_response :created

    request_uri = JSON.parse(response.body)["request_uri"]

    sign_in_as(@actor)
    visit(request_uri)
    consent!

    assert redirected["code"].present?
  end

  test "a pushed request may not speak for another client" do
    other = register(client_name: "Other")
    host! host_for(@tenant)

    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(
      @registration["client_id"], @registration["client_secret"]
    )

    post "/par",
         params: {
           response_type: "code", client_id: other["client_id"],
           redirect_uri: OidcFlow::REDIRECT_URI, scope: "openid"
         },
         headers: { "HTTP_AUTHORIZATION" => credentials }

    assert_response :bad_request
    assert_equal "invalid_request", JSON.parse(response.body)["error"]
  end

  test "a pushed request may not carry a request_uri of its own" do
    push(request_uri: "#{PushedRequest::PREFIX}borrowed")

    assert_response :bad_request
    assert_equal "invalid_request", JSON.parse(response.body)["error"]
  end

  test "a pushed request is held to the redirect_uris the client registered" do
    push(redirect_uri: "https://evil.example.com/cb")

    assert_response :bad_request
    assert_equal "invalid_request", JSON.parse(response.body)["error"]
  end

  test "a client that requires pushing refuses an ordinary authorize link" do
    within(@tenant) do
      Client.authenticating(@registration["client_id"]).update!(require_pushed_authorization_requests: true)
    end

    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"])

    assert_response :redirect
    assert_equal "invalid_request", redirected["error"]
    assert_match "push its authorization request", redirected["error_description"]
    assert_nil redirected["code"]
  end

  test "a client that requires pushing still answers a request it pushed" do
    within(@tenant) do
      Client.authenticating(@registration["client_id"]).update!(require_pushed_authorization_requests: true)
    end

    request_uri = push["request_uri"]

    sign_in_as(@actor)
    visit(request_uri)
    consent!

    assert redirected["code"].present?
  end

  test "discovery names the endpoint a client pushes to" do
    get "/.well-known/openid-configuration"

    metadata = JSON.parse(response.body)

    assert_equal "#{origin_for(@tenant)}/par", metadata["pushed_authorization_request_endpoint"]
    assert_equal false, metadata["require_pushed_authorization_requests"]
  end

  test "a registration says whether the client has to push" do
    registered = register(client_name: "Pushy", require_pushed_authorization_requests: true)

    assert_equal true, registered["require_pushed_authorization_requests"]

    within(@tenant) do
      assert Client.authenticating(registered["client_id"]).require_pushed_authorization_requests?
    end
  end
end
