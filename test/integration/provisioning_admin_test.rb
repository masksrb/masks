require "test_helper"
require_relative "../support/saml_idp"

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

  test "a manager registers a SAML application from the metadata it publishes" do
    key = OpenSSL::PKey::RSA.generate(2048)
    certificate = Base64.strict_encode64(SamlIdp.certificate_for(key, name: "wiki.example.com").to_der)
    xml = <<~XML
      <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://wiki.example.com/saml">
        <md:SPSSODescriptor AuthnRequestsSigned="true" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          <md:KeyDescriptor use="signing">
            <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:X509Data><ds:X509Certificate>#{certificate}</ds:X509Certificate></ds:X509Data></ds:KeyInfo>
          </md:KeyDescriptor>
          <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
          <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://wiki.example.com/wrong" index="0"/>
          <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://wiki.example.com/saml/acs" index="1"/>
        </md:SPSSODescriptor>
      </md:EntityDescriptor>
    XML

    read = ask("mutation($xml: String!) { readSamlApplicationMetadata(xml: $xml) { entityId acsUrls certificate nameIdFormat requestsSigned } }",
               xml: xml).dig("data", "readSamlApplicationMetadata")

    assert_equal "https://wiki.example.com/saml", read["entityId"]
    assert_equal [ "https://wiki.example.com/saml/acs" ], read["acsUrls"]
    assert_equal certificate, read["certificate"]
    assert read["requestsSigned"]

    created = ask(<<~GRAPHQL, **read.transform_keys(&:to_sym)).dig("data", "createSamlApplication", "client")
      mutation($entityId: String!, $acsUrls: [String!]!, $certificate: String, $nameIdFormat: String, $requestsSigned: Boolean) {
        createSamlApplication(name: "Wiki", entityId: $entityId, acsUrls: $acsUrls, certificate: $certificate,
                              nameIdFormat: $nameIdFormat, requestsSigned: $requestsSigned) {
          client { clientId protocol samlEntityId samlRequestsSigned redirectUris grantTypes approvedBy { identifier } }
        }
      }
    GRAPHQL

    assert_equal "saml", created["protocol"]
    assert created["samlRequestsSigned"]
    assert_empty created["grantTypes"]
    assert_equal "manager", created.dig("approvedBy", "identifier")

    refused = ask("mutation { readSamlApplicationMetadata(xml: \"<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><x>&e;</x>\") { entityId } }")
    assert_match "document type", refused["errors"].first["message"]
  end
end
