require "test_helper"

class ClientScopeBoundsTest < ActionDispatch::IntegrationTest
  setup { host! host_for(@tenant) }

  def ceiling(value)
    @tenant.update!(dynamic_client_scopes: value)
  end

  def put_metadata(registered, **metadata)
    host! host_for(@tenant)

    put "/register/#{registered['client_id']}",
        params: { client_name: "Probe", redirect_uris: [ OidcFlow::REDIRECT_URI ] }
          .merge(metadata).to_json,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_AUTHORIZATION" => "Bearer #{registered['registration_access_token']}"
        }

    JSON.parse(response.body)
  end

  test "with no ceiling declared a registration keeps every scope it asked for" do
    body = register(scope: "openid profile admin uris:catalog:read")

    assert_response :created
    assert_equal "admin openid profile uris:catalog:read", body["scope"]
  end

  test "open registration cannot ask for a masks: scope, with no ceiling declared" do
    body = register(scope: "openid profile masks:manage")

    assert_response :bad_request
    assert_equal "invalid_client_metadata", body["error"]
    assert_match "masks:manage", body["error_description"]
  end

  test "the refusal covers the whole masks: namespace, not one scope" do
    body = register(scope: "openid masks:clients:register")

    assert_response :bad_request
    assert_match "masks:clients:register", body["error_description"]
  end

  test "a registration update cannot add a masks: scope either" do
    registered = register
    widened = put_metadata(registered, scope: "openid masks:manage")

    assert_response :bad_request
    assert_equal [ "email", "offline_access", "openid", "profile" ], within(@tenant) {
      Client.authenticating(registered["client_id"]).scope_list.sort
    }
  end

  test "a ceiling trims a registration rather than refusing it" do
    ceiling "openid profile email offline_access uris:catalog:read"

    body = register(scope: "openid profile admin uris:catalog:read")

    assert_response :created
    assert_equal "openid profile uris:catalog:read", body["scope"]
  end

  test "a registration asking for nothing inside the ceiling is refused" do
    ceiling "openid profile"

    body = register(scope: "admin uris:catalog:write")

    assert_response :bad_request
    assert_equal "invalid_client_metadata", body["error"]
    assert_match "admin uris:catalog:write", body["error_description"]
  end

  test "a registration update cannot widen past the ceiling" do
    ceiling "openid profile email offline_access"

    registered = register
    widened = put_metadata(registered, scope: "openid admin")

    assert_response :success
    assert_equal "openid", widened["scope"]
    assert_equal [ "openid" ], within(@tenant) {
      Client.authenticating(registered["client_id"]).scope_list
    }
  end

  test "a registration update naming no scope at all leaves them alone" do
    registered = register
    updated = put_metadata(registered, client_name: "Renamed")

    assert_response :success
    assert_equal "Renamed", updated["client_name"]
    assert_equal registered["scope"], updated["scope"]
  end

  test "an approved client's scopes are not writable through its registration token" do
    client = within(@tenant) do
      Client.create!(
        client_id: SecureRandom.uuid, name: "Approved",
        redirect_uris: [ OidcFlow::REDIRECT_URI ],
        allowed_scopes: "openid uris:catalog:read",
        approved_at: Time.current, dynamic: false
      ).tap(&:issue_credentials!)
    end

    updated = put_metadata(
      { "client_id" => client.client_id, "registration_access_token" => client.registration_token },
      scope: "openid uris:catalog:read admin"
    )

    assert_response :success
    assert_equal "openid uris:catalog:read", updated["scope"]
  end

  test "a required scope is granted whether or not the client asked for it" do
    client = create_client(required_scopes: "openid", allowed_scopes: "profile email")

    assert_equal %w[email openid profile], client.scope_list
    assert_equal %w[openid profile], client.permitted_scopes("profile")
    assert_equal %w[openid], client.permitted_scopes("openid")
  end

  test "an allowed scope is granted only on request" do
    client = create_client(required_scopes: "openid", allowed_scopes: "profile email")

    assert_equal %w[openid], client.permitted_scopes("openid")
    assert_equal %w[email openid profile], client.permitted_scopes(nil)
  end
end
