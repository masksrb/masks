module Masks
  module Server
    require "test_helper"

    class ClientMetadataDocumentTest < ActionDispatch::IntegrationTest
      DOCUMENT_URL = "https://app.example.com/oauth/client.json".freeze

      setup do
        @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
        host! host_for(@tenant)
      end

      def publish(headers: {}, **document)
        stub_request(:get, DOCUMENT_URL).to_return(
          status: 200,
          body: {
            client_id: DOCUMENT_URL,
            client_name: "Document App",
            redirect_uris: [ OidcFlow::REDIRECT_URI ],
            grant_types: %w[authorization_code refresh_token],
            scope: "openid profile email offline_access"
          }.merge(document).compact.to_json,
          headers: { "Content-Type" => "application/json" }.merge(headers)
        )
      end

      def held
        within { Client.find_by(client_id: DOCUMENT_URL) }
      end

      test "discovery says a client_id may be the URL of a metadata document" do
        get "/.well-known/openid-configuration"

        assert_equal true, JSON.parse(response.body)["client_id_metadata_document_supported"]
      end

      test "a client named by the URL of its metadata document signs a person in with PKCE" do
        publish
        sign_in_as(@actor)

        authorize(client_id: DOCUMENT_URL)
        assert awaiting_consent?, "a client nobody approved asks for consent"
        assert_equal "Document App", auth_data.dig("client", "name")
        consent!

        body = token(
          grant_type: "authorization_code", code: code_from,
          redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier, client_id: DOCUMENT_URL
        )

        assert_equal DOCUMENT_URL, claims_in(body["id_token"])["aud"]
        assert_equal DOCUMENT_URL, claims_in(body["access_token"])["client_id"]

        client = held
        assert client.dynamic?
        assert client.public?
        assert_not client.approved?
        assert within { Event.exists?(action: Event::CLIENT_REGISTERED, client: client) }
      end

      test "the document is read once and kept for as long as its cache headers allow" do
        publish(headers: { "Cache-Control" => "max-age=7200" })
        sign_in_as(@actor)

        authorize(client_id: DOCUMENT_URL)
        authorize(client_id: DOCUMENT_URL)

        assert_requested :get, DOCUMENT_URL, times: 1
        assert_in_delta 2.hours.from_now, held.metadata_expires_at, 5.seconds
      end

      test "a stale document is read again and its changes are applied" do
        publish
        sign_in_as(@actor)
        authorize(client_id: DOCUMENT_URL)

        publish(client_name: "Renamed App")
        travel 2.hours do
          authorize(client_id: DOCUMENT_URL)
        end

        assert_equal "Renamed App", held.name
      end

      test "a lifetime outside five minutes and a day is held to those bounds" do
        publish(headers: { "Cache-Control" => "max-age=31536000" })
        authorize(client_id: DOCUMENT_URL)
        assert_in_delta 24.hours.from_now, held.metadata_expires_at, 5.seconds

        within { held.update!(metadata_expires_at: 1.minute.ago) }
        publish(headers: { "Cache-Control" => "no-store" })
        authorize(client_id: DOCUMENT_URL)
        assert_in_delta 5.minutes.from_now, held.metadata_expires_at, 5.seconds
      end

      test "a grant type masks does not offer is left off the client, as Claude's document lists jwt-bearer" do
        publish(grant_types: %w[authorization_code refresh_token urn:ietf:params:oauth:grant-type:jwt-bearer])
        sign_in_as(@actor)

        authorize(client_id: DOCUMENT_URL)

        assert awaiting_consent?
        assert_equal %w[authorization_code refresh_token], held.grant_types
      end

      test "a document that asks only for grant types masks does not offer is refused" do
        publish(grant_types: %w[urn:ietf:params:oauth:grant-type:jwt-bearer])

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_nil held
      end

      test "a document that declares no scope, as Claude's does, may ask for anything inside the ceiling" do
        @tenant.update!(dynamic_client_scopes: "openid profile email offline_access xixo:catalog:read")
        publish(scope: nil)
        sign_in_as(@actor)

        authorize(client_id: DOCUMENT_URL, scope: "openid xixo:catalog:read")

        assert awaiting_consent?
        assert_includes held.scope_list, "xixo:catalog:read"
      end

      test "a document that names another client_id is refused" do
        publish(client_id: "https://elsewhere.example.com/client.json")

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_match "client metadata document", response.body
        assert_nil held
      end

      test "a document may not hold a shared secret or authenticate with one" do
        publish(client_secret: "hunter2")
        authorize(client_id: DOCUMENT_URL)
        assert_response :bad_request

        within { ::Rails.cache.delete(ClientMetadataDocument.refusal_key(DOCUMENT_URL)) }
        publish(token_endpoint_auth_method: "client_secret_basic")
        authorize(client_id: DOCUMENT_URL)
        assert_response :bad_request
        assert_nil held
      end

      test "a refused document is not fetched again for five minutes" do
        stub_request(:get, DOCUMENT_URL).to_return(status: 404)

        authorize(client_id: DOCUMENT_URL)
        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_requested :get, DOCUMENT_URL, times: 1
      end

      test "a document cannot claim a resource" do
        publish(resources: [ "https://bank.example.com/api" ])

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_nil held
      end

      test "a document larger than five kilobytes is refused" do
        publish(client_name: "x" * 6.kilobytes)

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_nil held
      end

      test "a redirect_uri the document does not list is refused" do
        publish(redirect_uris: [ "https://app.example.com/elsewhere" ])

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
      end

      test "a document asks for no more than the tenant's ceiling and never a masks scope" do
        publish(scope: "openid masks:manage")

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_nil held
      end

      test "an archived document client stays refused" do
        publish
        authorize(client_id: DOCUMENT_URL)
        within { held.update!(archived_at: Time.current, metadata_expires_at: 1.minute.ago) }

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_requested :get, DOCUMENT_URL, times: 1
      end

      test "a tenant that turns registration off reads no documents" do
        within { @tenant.update!(dynamic_registration: Tenant::REGISTRATION_OFF) }
        publish

        authorize(client_id: DOCUMENT_URL)

        assert_response :bad_request
        assert_not_requested :get, DOCUMENT_URL
      end

      test "a URL with no path, a fragment, or dot segments is never fetched" do
        [ "https://app.example.com", "https://app.example.com/", "https://app.example.com/a#b",
          "https://app.example.com/a/../client.json", "https://user:pass@app.example.com/client.json" ].each do |url|
          assert_not ClientMetadataDocument.url?(url), url
        end

        assert ClientMetadataDocument.url?(DOCUMENT_URL)
      end
    end
  end
end
