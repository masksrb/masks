require "test_helper"

class ResourceIndicatorsTest < ActionDispatch::IntegrationTest
  MCP = "https://probe.example.com/mcp".freeze
  FILES = "https://probe.example.com/files".freeze

  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  def redeem(code, **params)
    token(
      grant_type: "authorization_code", code: code,
      redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
      client_id: @registration["client_id"], client_secret: @registration["client_secret"],
      **params
    )
  end

  test "a repeated resource parameter survives Rails keeping only the last" do
    code = authorized_code(actor: @actor, registration: @registration, resource: [ MCP, FILES ])
    claims = claims_in(redeem(code)["access_token"])

    assert_equal [ FILES, MCP ], Array(claims["aud"]).sort
  end

  test "a single resource becomes a single-valued aud" do
    code = authorized_code(actor: @actor, registration: @registration, resource: MCP)

    assert_equal MCP, claims_in(redeem(code)["access_token"])["aud"]
  end

  test "the token endpoint may narrow to a subset of what was authorized" do
    code = authorized_code(actor: @actor, registration: @registration, resource: [ MCP, FILES ])

    assert_equal MCP, claims_in(redeem(code, resource: MCP)["access_token"])["aud"]
  end

  test "the token endpoint cannot ask for a resource the code did not carry" do
    code = authorized_code(actor: @actor, registration: @registration, resource: MCP)
    body = redeem(code, resource: FILES)

    assert_equal "invalid_target", body["error"]
    assert_match FILES, body["error_description"]
  end

  test "a request naming no resource falls back to the client's own id" do
    code = authorized_code(actor: @actor, registration: @registration)

    assert_equal @registration["client_id"], claims_in(redeem(code)["access_token"])["aud"]
  end

  test "a code carrying no audience is held to the client, not to whatever the token endpoint names" do
    code = authorized_code(actor: @actor, registration: @registration)
    body = redeem(code, resource: FILES)

    assert_equal "invalid_target", body["error"]
    assert_match FILES, body["error_description"]
  end

  test "a code carrying no audience may still name the client the person consented to" do
    code = authorized_code(actor: @actor, registration: @registration)
    claims = claims_in(redeem(code, resource: @registration["client_id"])["access_token"])

    assert_equal @registration["client_id"], claims["aud"]
  end

  test "a resource that is not an absolute URI is refused at authorize" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], resource: "not-a-uri")

    assert_equal "invalid_target", redirected["error"]
  end

  test "a resource carrying a fragment is refused at authorize" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], resource: "#{MCP}#part")

    assert_equal "invalid_target", redirected["error"]
  end

  test "the consent screen names the resources it is being asked to cover" do
    sign_in_as(@actor)
    authorize(client_id: @registration["client_id"], resource: MCP)

    assert_response :success
    assert awaiting_consent?
    assert_match MCP, response.body
  end

  test "consent remembered for one resource does not cover another" do
    authorized_code(actor: @actor, registration: @registration, resource: MCP)

    authorize(client_id: @registration["client_id"], resource: FILES)

    assert awaiting_consent?
  end
end
