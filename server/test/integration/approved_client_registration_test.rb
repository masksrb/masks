require "test_helper"

class ApprovedClientRegistrationTest < ActionDispatch::IntegrationTest
  APP = "https://jons.things.test".freeze
  RESOURCE = "#{APP}/mcp".freeze

  setup do
    @owner = create_actor(@tenant, nickname: "owner", password: "password",
                          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))
    host! host_for(@tenant)
  end

  def paired
    sign_in_as(@owner)

    query = [
      [ "client_name", "things" ],
      [ "resource", RESOURCE ],
      [ "scope", "openid profile email" ],
      [ "return_to", "#{APP}/auth/handshake/callback" ],
      [ "redirect_uris", "#{APP}/auth/masks/callback" ]
    ]

    get "/handshake?#{URI.encode_www_form(query)}"
    post "/handshake", params: { approve: "yes", hid: response.body[/name="hid"[^>]*value="([^"]*)"/, 1] }

    secret = Rack::Utils.parse_query(URI.parse(response.location).query)["initial_access_token"]

    post "/register",
         params: {}.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{secret}" }

    JSON.parse(response.body)
  end

  def amend(registration, **metadata)
    put "/register/#{registration['client_id']}",
        params: metadata.to_json,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_AUTHORIZATION" => "Bearer #{registration['registration_access_token']}"
        }

    JSON.parse(response.body)
  end

  test "an approved client cannot be re-pointed at another origin by its own registration token" do
    registration = paired

    amended = amend(
      registration,
      redirect_uris: [ "https://elsewhere.test/cb" ],
      post_logout_redirect_uris: [ "https://elsewhere.test/done" ]
    )

    assert_response :success
    assert_equal registration["redirect_uris"], amended["redirect_uris"]
    assert_equal [ "#{APP}/auth/masks/callback" ], within(@tenant) { Client.approved.sole.redirect_uris }
  end

  test "an approved client cannot drop its authentication with its own registration token" do
    registration = paired

    assert_equal "client_secret_basic", registration["token_endpoint_auth_method"]

    amended = amend(registration, token_endpoint_auth_method: "none")

    assert_equal "client_secret_basic", amended["token_endpoint_auth_method"]
    refute within(@tenant) { Client.approved.sole.public? }
  end

  test "an approved client cannot claim another resource, which is what approval was for" do
    registration = paired

    amend(registration, resources: [ "https://elsewhere.test/mcp" ])

    assert_equal [ RESOURCE ], within(@tenant) { Client.approved.sole.resources }
  end

  test "what a human did not approve is still the client's to describe" do
    registration = paired

    amended = amend(registration, client_name: "things, renamed", logo_uri: "https://jons.things.test/logo.png")

    assert_equal "things, renamed", amended["client_name"]
    assert_equal "https://jons.things.test/logo.png", amended["logo_uri"]
  end

  test "a dynamic client still describes its own redirect uris" do
    registration = register(@tenant, client_name: "dynamic")

    amended = amend(registration, redirect_uris: [ "https://probe.example.com/moved" ])

    assert_equal [ "https://probe.example.com/moved" ], amended["redirect_uris"]
  end
end
