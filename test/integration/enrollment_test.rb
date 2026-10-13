module Masks
  module Server
    require "test_helper"
    require_relative "../support/dpop"

    class EnrollmentTest < ActionDispatch::IntegrationTest
      include DpopProofs

      RESOURCE = "https://xixo.example.com/mcp".freeze
      ASSERTION = ClientAssertion::TYPE

      setup do
        host! host_for(@tenant)
        @owner = owner
        @machine_key = OpenSSL::PKey::EC.generate("prime256v1")
      end

      def owner(namespace: "xixo:", **attributes)
        within do
          client = Client.new(
            client_id: SecureRandom.uuid, name: "xixo",
            grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
            redirect_uris: [ "https://xixo.example.com/auth/masks/callback" ],
            resources: [ RESOURCE ], allowed_scopes: "openid profile",
            approved_at: Time.current, **attributes
          )

          client.issue_secret!
          client.save!
          Namespace.create!(name: namespace, client: client, resource: RESOURCE, claimed_at: Time.current) if namespace
          client
        end
      end

      def enroll(client = @owner, secret: client.secret, **params)
        post "/enrollments",
             params: { client_id: client.client_id, client_secret: secret, scope: "xixo:agent" }.merge(params)

        JSON.parse(response.body)
      end

      def machine_jwks(key = @machine_key)
        { "keys" => [ JWT::JWK.new(key, kid: "machine").export.transform_keys(&:to_s) ] }
      end

      def redeem(secret, **metadata)
        post "/register",
             params: { client_name: "nas", jwks: machine_jwks }.merge(metadata).compact.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{secret}" }

        JSON.parse(response.body)
      end

      def assertion(client_id, key: @machine_key, audience: origin_for(@tenant))
        now = Time.current.to_i

        JWT.encode({
          "iss" => client_id, "sub" => client_id, "aud" => audience,
          "iat" => now, "exp" => now + 60, "jti" => SecureRandom.uuid
        }, key, "ES256", { kid: "machine" })
      end

      def machine_token(client_id, proven: true, key: @machine_key)
        headers = proven ? with_dpop(method: "POST", url: "#{origin_for(@tenant)}/token") : {}

        post "/token",
             params: { grant_type: Client::CLIENT_CREDENTIALS, client_assertion_type: ASSERTION,
                       client_assertion: assertion(client_id, key: key) },
             headers: headers

        JSON.parse(response.body)
      end

      test "an app with a namespace enrolls a machine that signs in as itself with its own key" do
        issued = enroll(client_name: "nas")

        assert_response :created
        assert_equal "xixo:agent", issued["scope"]
        assert_in_delta 900, issued["expires_in"], 1

        registration = redeem(issued["initial_access_token"])

        assert_response :created
        assert_nil registration["client_secret"]
        assert registration["registration_access_token"]
        assert_equal "private_key_jwt", registration["token_endpoint_auth_method"]
        assert_equal [ Client::CLIENT_CREDENTIALS ], registration["grant_types"]
        assert registration["dpop_bound_access_tokens"]

        machine = within { Client.find_by!(client_id: registration["client_id"]) }

        assert_equal "nas", machine.name
        assert_equal @owner.id, machine.enrolled_by_id
        assert machine.approved?

        granted = machine_token(machine.client_id)
        claims = claims_in(granted["access_token"])

        assert_equal "DPoP", granted["token_type"]
        assert_equal "xixo:agent", granted["scope"]
        assert_equal RESOURCE, claims["aud"]
        assert_equal machine.client_id, claims["sub"]
        assert_equal dpop_jkt, claims.dig("cnf", "jkt")
      end

      test "a machine signs in to masks mounted under a path with a proof for the address it posts to" do
        registration = redeem(enroll["initial_access_token"])
        mounted = "#{origin_for(@tenant)}/id"

        post "/token",
             params: { grant_type: Client::CLIENT_CREDENTIALS, client_assertion_type: ASSERTION,
                       client_assertion: assertion(registration["client_id"], audience: mounted) },
             headers: with_dpop(method: "POST", url: "#{mounted}/token"),
             env: { "SCRIPT_NAME" => "/id" }

        assert_response :success
        assert_equal "DPoP", JSON.parse(response.body)["token_type"]
      end

      test "an enrolled machine's token must be held to a key" do
        issued = enroll
        registration = redeem(issued["initial_access_token"])

        assert_equal "invalid_dpop_proof", machine_token(registration["client_id"], proven: false)["error"]
      end

      test "the endpoint is published in discovery" do
        get "/.well-known/openid-configuration"

        assert_equal "#{origin_for(@tenant)}/enrollments", JSON.parse(response.body)["enrollment_endpoint"]
      end

      test "an app without a namespace enrolls nothing" do
        bare = owner(namespace: nil, name: "bare", resources: [ "https://bare.example.com/mcp" ])

        assert_equal "invalid_request", enroll(bare)["error"]
        assert_response :bad_request
      end

      test "a scope outside the app's namespace is refused" do
        %w[other:agent openid profile xixo: xixo:agent\ email].each do |scope|
          assert_equal "invalid_request", enroll(scope: scope)["error"], scope
        end
      end

      test "a masks scope is refused" do
        %w[masks:manage masks:manage:security masks:handshake masks:delegate:google].each do |scope|
          assert_equal "invalid_request", enroll(scope: scope)["error"], scope
        end
      end

      test "a client that does not authenticate is refused" do
        assert_equal "invalid_client", enroll(secret: "nope")["error"]
        assert_response :unauthorized
      end

      test "a public app enrolls nothing, since it proves nothing about itself" do
        spa = owner(namespace: "spa:", name: "spa", token_endpoint_auth_method: "none")

        post "/enrollments", params: { client_id: spa.client_id, scope: "spa:agent" }

        assert_response :unauthorized
        assert_equal "invalid_client", JSON.parse(response.body)["error"]
        assert_not within { EnrollmentToken.exists?(client: spa) }
      end

      test "a token minted before the app went public no longer enrolls" do
        secret = enroll["initial_access_token"]

        within { @owner.update_columns(token_endpoint_auth_method: "none") }

        assert_equal "invalid_client_metadata", redeem(secret)["error"]
        assert_equal 0, within { @owner.enrolled.count }
      end

      test "an archived app enrolls nothing" do
        within { @owner.update!(archived_at: Time.current) }

        assert_equal "invalid_client", enroll["error"]
      end

      test "an enrollment token is used once" do
        secret = enroll["initial_access_token"]

        redeem(secret)
        assert_response :created

        assert_equal "invalid_token", redeem(secret, client_name: "again")["error"]
        assert_response :unauthorized
        assert_equal 1, within { @owner.enrolled.count }
      end

      test "an enrollment token expires" do
        secret = enroll(expires_in: 60)["initial_access_token"]

        travel 61.seconds do
          assert_equal "invalid_token", redeem(secret)["error"]
        end
      end

      test "a lifetime outside a minute to an hour is refused" do
        %w[59 3601 soon].each do |lifetime|
          assert_equal "invalid_request", enroll(expires_in: lifetime)["error"], lifetime
        end
      end

      test "redeeming without keys is refused and leaves the token unspent" do
        secret = enroll["initial_access_token"]

        assert_equal "invalid_client_metadata", redeem(secret, jwks: nil)["error"]
        assert_equal "invalid_client_metadata", redeem(secret, jwks: nil, jwks_uri: "https://nas.example.com/jwks")["error"]

        redeem(secret)
        assert_response :created
      end

      test "private keys are refused" do
        private_jwks = { "keys" => [ JWT::JWK.new(@machine_key).export(include_private: true).transform_keys(&:to_s) ] }

        assert_equal "invalid_client_metadata", redeem(enroll["initial_access_token"], jwks: private_jwks)["error"]
      end

      def reregister(registration, **metadata)
        put "/register/#{registration['client_id']}",
            params: metadata.to_json,
            headers: { "CONTENT_TYPE" => "application/json",
                       "HTTP_AUTHORIZATION" => "Bearer #{registration['registration_access_token']}" }
      end

      test "a short RSA key or an unknown curve is refused" do
        short = { "keys" => [ JWT::JWK.new(OpenSSL::PKey::RSA.generate(1024), kid: "short").export.transform_keys(&:to_s) ] }
        odd = machine_jwks.deep_dup.tap { |held| held["keys"].first["crv"] = "P-256K" }
        long = { "keys" => [ JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "long").export.transform_keys(&:to_s) ] }

        assert_match "at least 2048 bits", redeem(enroll["initial_access_token"], jwks: short)["error_description"]
        assert_match "P-256K is not a curve", redeem(enroll["initial_access_token"], jwks: odd)["error_description"]

        redeem(enroll["initial_access_token"], jwks: long)
        assert_response :created
      end

      test "a machine cannot widen what it was enrolled with" do
        registration = redeem(enroll["initial_access_token"])

        reregister(registration, scope: "xixo:settings:admin", grant_types: [ "authorization_code" ],
                                 token_endpoint_auth_method: "client_secret_basic", resources: [ "https://elsewhere.example.com" ])

        assert_response :forbidden

        machine = within { Client.find_by!(client_id: registration["client_id"]) }

        assert_equal "xixo:agent", machine.allowed_scopes
        assert_equal [ Client::CLIENT_CREDENTIALS ], machine.grant_types
        assert_equal Client::PRIVATE_KEY_JWT, machine.token_endpoint_auth_method
        assert_equal [ RESOURCE ], machine.resources
      end

      test "a machine cannot swap its keys with its registration access token" do
        registration = redeem(enroll["initial_access_token"])
        stolen = OpenSSL::PKey::EC.generate("prime256v1")

        reregister(registration, client_name: "renamed", jwks: machine_jwks(stolen))

        assert_response :forbidden
        machine = within { Client.find_by!(client_id: registration["client_id"]) }
        assert_equal "nas", machine.name
        assert_equal machine_jwks["keys"].first["x"], machine.jwks["keys"].first["x"]
        assert_equal "invalid_client", machine_token(registration["client_id"], key: stolen)["error"]
      end

      test "a machine that deletes its own registration is unenrolled" do
        registration = redeem(enroll["initial_access_token"])
        machine_token(registration["client_id"])

        delete "/register/#{registration['client_id']}",
               headers: { "HTTP_AUTHORIZATION" => "Bearer #{registration['registration_access_token']}" }

        assert_response :no_content
        within do
          machine = Client.find_by!(client_id: registration["client_id"])

          assert machine.archived?
          assert_empty machine.tokens.live
          assert Event.exists?(action: Event::CLIENT_UNENROLLED, client: machine)
        end
      end

      test "an enrolled machine's access token lives ten minutes" do
        registration = redeem(enroll["initial_access_token"])

        assert_in_delta 600, machine_token(registration["client_id"])["expires_in"], 1
      end

      def introspect(token, client_id: @owner.client_id, **auth)
        auth = { client_secret: @owner.secret } if auth.empty? && client_id == @owner.client_id

        post "/introspect", params: { token: token, client_id: client_id }.merge(auth)

        JSON.parse(response.body)
      end

      test "a machine introspects its own token but no other client's" do
        other_key = OpenSSL::PKey::EC.generate("prime256v1")
        first = redeem(enroll["initial_access_token"])
        second = redeem(enroll["initial_access_token"], jwks: machine_jwks(other_key))
        token = machine_token(first["client_id"])["access_token"]

        assert introspect(token)["active"]

        assert introspect(token, client_id: first["client_id"], client_assertion_type: ASSERTION,
                                 client_assertion: assertion(first["client_id"]))["active"]

        refute introspect(token, client_id: second["client_id"], client_assertion_type: ASSERTION,
                                 client_assertion: assertion(second["client_id"], key: other_key))["active"]
      end

      test "a token whose client is archived is inactive" do
        registration = redeem(enroll["initial_access_token"])
        token = machine_token(registration["client_id"])["access_token"]

        within { Client.find_by!(client_id: registration["client_id"]).update_columns(archived_at: Time.current) }

        refute introspect(token)["active"]
      end

      test "archiving an app ends the tokens it holds itself" do
        enroll

        within do
          assert_predicate @owner.tokens.live, :any?

          @owner.reload.update!(archived_at: Time.current)

          assert_empty @owner.tokens.live
        end
      end

      test "a machine is never the approved client for its resource" do
        redeem(enroll["initial_access_token"])

        within do
          assert_equal @owner, Client.approved_for(RESOURCE)

          @owner.update_columns(archived_at: Time.current)

          assert_nil Client.approved_for(RESOURCE)
        end
      end

      test "a machine holds no namespace and so enrolls nothing itself" do
        registration = redeem(enroll["initial_access_token"])

        post "/enrollments",
             params: { client_assertion_type: ASSERTION, client_assertion: assertion(registration["client_id"]),
                       scope: "xixo:agent" }

        assert_equal "invalid_request", JSON.parse(response.body)["error"]
      end

      test "a token minted before the app lost its namespace no longer enrolls" do
        secret = enroll["initial_access_token"]

        within { Namespace.where(client: @owner).destroy_all }

        assert_equal "invalid_client_metadata", redeem(secret)["error"]
      end

      test "archiving the app archives every machine it enrolled and ends their tokens" do
        registration = redeem(enroll["initial_access_token"])
        granted = machine_token(registration["client_id"])

        within { @owner.reload.update!(archived_at: Time.current) }

        machine = within { Client.find_by!(client_id: registration["client_id"]) }

        assert machine.archived?
        within do
          assert_empty machine.tokens.live
          refute AccessToken.find_by(digest: claims_in(granted["access_token"])["jti"]).live?
        end
        assert_equal "invalid_client", machine_token(machine.client_id)["error"]
      end

      def unenroll(client_id, app = @owner, secret: app.secret)
        delete "/enrollments/#{client_id}", params: { client_id: app.client_id, client_secret: secret }
      end

      test "an app unenrolls its machine, which loses its tokens and can sign in no more" do
        registration = redeem(enroll["initial_access_token"])
        granted = machine_token(registration["client_id"])

        unenroll(registration["client_id"])

        assert_response :no_content

        within do
          machine = Client.find_by!(client_id: registration["client_id"])

          assert machine.archived?
          assert_empty machine.tokens.live
          assert Event.exists?(action: Event::CLIENT_UNENROLLED, client: machine)
          refute AccessToken.find_by(digest: claims_in(granted["access_token"])["jti"]).live?
        end

        assert_equal "invalid_client", machine_token(registration["client_id"])["error"]
      end

      test "unenrolling twice answers the same" do
        registration = redeem(enroll["initial_access_token"])

        unenroll(registration["client_id"])
        unenroll(registration["client_id"])

        assert_response :no_content
      end

      test "an app cannot unenroll another app's machine" do
        registration = redeem(enroll["initial_access_token"])
        other = owner(namespace: "other:")

        unenroll(registration["client_id"], other)

        assert_response :not_found
        refute within { Client.find_by!(client_id: registration["client_id"]).archived? }
      end

      test "an app cannot unenroll a client it did not enroll" do
        unenroll(owner(namespace: nil).client_id)

        assert_response :not_found
      end

      test "a public app unenrolls nothing, even a machine it once enrolled" do
        registration = redeem(enroll["initial_access_token"])

        within { @owner.update_columns(token_endpoint_auth_method: "none") }

        delete "/enrollments/#{registration['client_id']}", params: { client_id: @owner.client_id }

        assert_response :unauthorized
        assert_not within { Client.find_by!(client_id: registration["client_id"]).archived? }
      end

      test "unenrolling needs the app to authenticate" do
        registration = redeem(enroll["initial_access_token"])

        unenroll(registration["client_id"], secret: "wrong")

        assert_response :unauthorized
        refute within { Client.find_by!(client_id: registration["client_id"]).archived? }
      end

      test "both steps are recorded" do
        registration = redeem(enroll(client_name: "nas")["initial_access_token"])

        within do
          assert Event.exists?(action: Event::CLIENT_ENROLLMENT_ISSUED, client: @owner)
          assert Event.exists?(action: Event::CLIENT_ENROLLED, client: Client.find_by!(client_id: registration["client_id"]))
        end
      end
    end
  end
end
