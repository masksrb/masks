require "test_helper"

class TokenTypesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  LOGOUT_URI = "https://probe.example.com/logout/backchannel".freeze

  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register(backchannel_logout_uri: LOGOUT_URI)
    host! host_for(@tenant)
    @granted = access_token_for(actor: @actor, registration: @registration)
  end

  def header_of(jwt)
    JWT.decode(jwt, nil, false).last
  end

  def retyped(jwt, typ)
    claims = claims_in(jwt)

    within { issuer_for(@tenant).sign(claims, typ: typ) }
  end

  test "an access token is typed at+jwt and an id token is not" do
    assert_equal "at+jwt", header_of(@granted["access_token"])["typ"]
    assert_equal "JWT", header_of(@granted["id_token"])["typ"]
  end

  test "an access token's claims signed as anything but at+jwt are not accepted as one" do
    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{retyped(@granted['access_token'], 'JWT')}" }

    assert_response :unauthorized
  end

  test "an access token is not introspected when it is typed as something else" do
    post "/introspect",
         params: URI.encode_www_form(token: retyped(@granted["access_token"], "JWT"),
                                     client_id: @registration["client_id"],
                                     client_secret: @registration["client_secret"]),
         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_equal false, JSON.parse(response.body)["active"]
  end

  test "an access token is not an id_token_hint" do
    get "/logout", params: { id_token_hint: @granted["access_token"] }

    assert_response :bad_request
  end

  test "a logout token is typed logout+jwt" do
    delivered = []

    stub_request(:post, LOGOUT_URI).to_return do |request|
      delivered << Rack::Utils.parse_query(request.body)["logout_token"]
      { status: 200 }
    end

    perform_enqueued_jobs { delete "/login" }

    assert_equal "logout+jwt", header_of(delivered.first)["typ"]
  end
end
