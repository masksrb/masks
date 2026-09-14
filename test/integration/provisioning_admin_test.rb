require "test_helper"

class ProvisioningAdminTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @manager = create_actor(@tenant, nickname: "manager", scopes: "openid profile email masks:manage")
    @console = create_client(@tenant, name: "Console", allowed_scopes: "openid profile email masks:manage",
                                      approved_at: Time.current, grant_types: [ "authorization_code" ])
  end

  def bearer
    @bearer ||= begin
      sign_in_as(@manager)
      authorize(client_id: @console.client_id, scope: "openid masks:manage", resource: issuer_for(@tenant).manage_resource)
      consent! if awaiting_consent?

      token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
            code_verifier: verifier, client_id: @console.client_id)["access_token"]
    end
  end

  def ask(query, **variables)
    post "/manage/graphql", params: { query: query, variables: variables }.to_json,
                            headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{bearer}" }

    JSON.parse(response.body)
  end

  test "a manager issues a provisioning token, sees it listed, and revokes it" do
    issued = ask('mutation { issueProvisioningToken(label: "Okta", expiresIn: 86400) { secret provisioningToken { id label expiresAt } } }')
      .dig("data", "issueProvisioningToken")

    assert issued["secret"].present?
    assert_operator Time.zone.parse(issued.dig("provisioningToken", "expiresAt")), :<=, 1.day.from_now

    listed = ask("{ scimBaseUrl provisioningTokens { id label issuedBy { identifier } } }")["data"]

    assert_equal "#{origin_for(@tenant)}/scim/v2", listed["scimBaseUrl"]
    assert_equal [ "Okta" ], listed["provisioningTokens"].map { |token| token["label"] }
    assert_equal "manager", listed["provisioningTokens"].first.dig("issuedBy", "identifier")

    id = issued.dig("provisioningToken", "id")
    ask("mutation($id: ID!) { revokeProvisioningToken(id: $id) { provisioningToken { id } } }", id: id)

    assert_empty ask("{ provisioningTokens { id } }").dig("data", "provisioningTokens")
    assert_nil within { ProvisioningToken.redeem(issued["secret"]) }
  end

  test "a manager suspends and restores somebody, but never themselves" do
    person = create_actor(@tenant, nickname: "person")

    body = ask("mutation($uuid: ID!) { suspendActor(uuid: $uuid) { actor { suspendedAt } } }", uuid: person.uuid)
    assert body.dig("data", "suspendActor", "actor", "suspendedAt").present?

    assert_equal [ "person" ], ask("{ actors(suspended: true) { identifier } }").dig("data", "actors").map { |a| a["identifier"] }

    body = ask("mutation($uuid: ID!) { restoreActor(uuid: $uuid) { actor { suspendedAt } } }", uuid: person.uuid)
    assert_nil body.dig("data", "restoreActor", "actor", "suspendedAt")

    body = ask("mutation($uuid: ID!) { suspendActor(uuid: $uuid) { actor { suspendedAt } } }", uuid: @manager.uuid)
    assert_match "yourself", body["errors"].first["message"]
  end
end
