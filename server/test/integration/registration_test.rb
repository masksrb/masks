require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  setup { host! host_for(@tenant) }

  def manage(method, registration, tenant: @tenant, headers: {},
             token: registration["registration_access_token"], **options)
    host! host_for(tenant)

    send(method, "/register/#{registration['client_id']}",
         headers: { "HTTP_AUTHORIZATION" => "Bearer #{token}" }.merge(headers), **options)

    response
  end

  test "a client registers with no prior arrangement" do
    body = register

    assert_response :created
    assert body["client_id"].present?
    assert body["client_secret"].present?
    assert body["registration_access_token"].present?
    assert_equal "#{origin_for(@tenant)}/register/#{body['client_id']}",
                 body["registration_client_uri"]
    assert_equal 0, body["client_secret_expires_at"]
  end

  test "a public client is issued no secret" do
    body = register(token_endpoint_auth_method: "none")

    assert_response :created
    assert_nil body["client_secret"]
    assert_equal "none", body["token_endpoint_auth_method"]
  end

  test "registration metadata reads back against the access token" do
    registered = register

    manage(:get, registered)

    assert_response :success
    assert_equal registered["client_id"], JSON.parse(response.body)["client_id"]
  end

  test "the read-back never returns the secret again" do
    registered = register

    manage(:get, registered)

    assert_nil JSON.parse(response.body)["client_secret"]
  end

  test "metadata is updated in place" do
    registered = register

    manage(:put, registered,
           params: { client_name: "Renamed", redirect_uris: [ OidcFlow::REDIRECT_URI ] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" })

    assert_response :success
    assert_equal "Renamed", JSON.parse(response.body)["client_name"]
  end

  test "a deleted registration stops answering" do
    registered = register

    manage(:delete, registered)
    assert_response :no_content

    manage(:get, registered)
    assert_response :unauthorized
  end

  test "a wrong registration token is refused" do
    registered = register

    manage(:get, registered, token: SecureRandom.urlsafe_base64(48))

    assert_response :unauthorized
    assert_match "Bearer", response.headers["WWW-Authenticate"]
  end

  test "a registration token is refused against another tenant" do
    registered = register

    manage(:get, registered, tenant: other_tenant)

    assert_response :unauthorized
  end

  test "a registration token is refused against another client" do
    mine = register
    theirs = register(client_name: "Theirs")

    manage(:get, theirs, token: mine["registration_access_token"])

    assert_response :unauthorized
  end

  test "a redirect_uri with a fragment is refused" do
    body = register(redirect_uris: [ "https://probe.example.com/cb#done" ])

    assert_response :bad_request
    assert_equal "invalid_client_metadata", body["error"]
    assert_match "fragment", body["error_description"]
  end

  test "a relative redirect_uri is refused" do
    body = register(redirect_uris: [ "/cb" ])

    assert_response :bad_request
    assert_match "absolute", body["error_description"]
  end

  test "registration without a redirect_uri is refused" do
    body = register(redirect_uris: [])

    assert_response :bad_request
    assert_match "at least one", body["error_description"]
  end

  test "an unsupported grant type is refused" do
    body = register(grant_types: [ "password" ])

    assert_response :bad_request
    assert_match "password", body["error_description"]
  end

  test "a client registered here is unknown to another tenant" do
    registered = register

    host! host_for(other_tenant)
    authorize(client_id: registered["client_id"])

    assert_response :bad_request
    assert_select "#authorize-error[data-error=?]", "invalid_client"
  end

  test "an unknown client_id is handed back when the redirect_uri is one masks serves" do
    authorize(
      client_id: SecureRandom.uuid,
      redirect_uri: "#{origin_for(@tenant)}/manage/callback",
      state: "console"
    )

    assert_response :redirect
    assert_equal "invalid_client", redirected["error"]
    assert_equal "console", redirected["state"]
    assert_equal origin_for(@tenant), redirected["iss"]
  end

  test "an unknown client_id dead-ends when the redirect_uri belongs to someone else" do
    authorize(client_id: SecureRandom.uuid, redirect_uri: "#{origin_for(other_tenant)}/manage/callback")

    assert_response :bad_request
    assert_select "#authorize-error[data-error=?]", "invalid_client"
  end
end
