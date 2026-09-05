require "test_helper"

class NamespaceScopeTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @client = Tenant.switch(@tenant) do
      Client.create!(
        client_id: SecureRandom.uuid,
        name: "Thingies",
        redirect_uris: [ OidcFlow::REDIRECT_URI ],
        allowed_scopes: "openid profile email offline_access things:",
        grant_types: [ "authorization_code" ],
        response_types: [ "code" ],
        token_endpoint_auth_method: "none",
        dynamic: false,
        approved_at: Time.current
      )
    end
  end

  def refusal
    return nil unless response.redirect?

    URI.decode_www_form(URI.parse(response.headers["Location"]).query).to_h
  end

  test "a namespace grant covers a scope nobody registered by name" do
    authorize(client_id: @client.client_id, scope: "openid things:catalog:read things:settings:admin")

    assert_nil refusal&.dig("error"),
               "a client granted things: may ask for anything beneath it"
  end

  test "a namespace grant does not reach past its own prefix" do
    authorize(client_id: @client.client_id, scope: "openid things:catalog:read masks:manage")

    assert_equal "invalid_scope", refusal["error"]
    assert_equal "this client may not request masks:manage", refusal["error_description"]
  end

  test "the bare namespace is not a scope anyone can ask for" do
    authorize(client_id: @client.client_id, scope: "openid things:")

    assert_equal "invalid_scope", refusal["error"]
    assert_equal "this client may not request things:", refusal["error_description"]
  end

  test "what is granted is the scope asked for, never the prefix itself" do
    Tenant.switch(@tenant) do
      granted = @client.permitted_scopes(%w[things:catalog:read things:settings:admin])

      assert_equal %w[things:catalog:read things:settings:admin], granted - Scopes::STANDARD
      assert_not_includes granted, "things:"
    end
  end
end
