module Masks
  module Server
    require "test_helper"

    class RichAuthorizationRequestsTest < ActionDispatch::IntegrationTest
      TYPE = "payment_initiation".freeze
      PAYMENT = {
        "type" => TYPE,
        "instructedAmount" => { "currency" => "EUR", "amount" => "123.50" },
        "creditorName" => "Merchant A"
      }.freeze
      SCHEMA = {
        "type" => "object",
        "required" => [ "instructedAmount" ],
        "properties" => {
          "instructedAmount" => {
            "type" => "object",
            "required" => %w[currency amount],
            "properties" => {
              "currency" => { "type" => "string", "enum" => %w[EUR USD] },
              "amount" => { "type" => "string", "maxLength" => 20 }
            }
          },
          "creditorName" => { "type" => "string", "maxLength" => 140 }
        }
      }.freeze

      setup do
        @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
        create_client(@tenant, name: "Bank", approved_at: Time.current,
                               authorization_details_schemas: { TYPE => { "label" => "Send a payment", "schema" => SCHEMA } })
        @registration = register(
          grant_types: [ "authorization_code", "refresh_token", Exchange::GRANT_TYPE ],
          authorization_details_types: [ TYPE ]
        )
        host! host_for(@tenant)
      end

      def asked(details = [ PAYMENT ], scope: "openid offline_access")
        sign_in_as(@actor)
        authorize(client_id: @registration["client_id"], scope: scope, state: SecureRandom.hex(8),
                  authorization_details: details.to_json)
      end

      def redeemed(**params)
        token(
          grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
          code_verifier: verifier, client_id: @registration["client_id"],
          client_secret: @registration["client_secret"], **params
        )
      end

      def granted
        asked
        consent!
        redeemed
      end

      test "discovery lists the types an approved client declared" do
        get "/.well-known/openid-configuration"

        assert_equal [ TYPE ], JSON.parse(response.body)["authorization_details_types_supported"]
      end

      test "the person sees each detail with its label before allowing it" do
        asked

        assert awaiting_consent?
        detail = auth_data.dig("consent", "details", 0)
        assert_equal "Send a payment", detail["label"]
        assert_equal TYPE, detail["type"]
        assert_includes detail["fields"], [ "creditorName", "Merchant A" ]
      end

      test "granted details reach the token response, the access token, and introspection" do
        body = granted

        assert_equal [ PAYMENT ], body["authorization_details"]
        assert_equal [ PAYMENT ], claims_in(body["access_token"])["authorization_details"]

        post "/introspect", params: { token: body["access_token"], client_id: @registration["client_id"],
                                      client_secret: @registration["client_secret"] }

        assert_equal [ PAYMENT ], JSON.parse(response.body)["authorization_details"]
        within { assert_equal [ TYPE ], Event.where(action: Event::CONSENT_GRANTED).last.details["authorization_details"] }
      end

      test "a type that is not remembered is asked about every time, even after allowing the client before" do
        granted
        asked

        assert awaiting_consent?
      end

      test "a type nobody declared is refused back to the client" do
        asked([ { "type" => "unknown_type" } ])

        assert_equal "invalid_authorization_details", redirected["error"]
        assert_match "not a type of authorization detail", redirected["error_description"]
      end

      test "a type the client did not register is refused" do
        @registration = register(authorization_details_types: [])

        asked

        assert_equal "invalid_authorization_details", redirected["error"]
      end

      test "an entry its schema does not allow is refused" do
        asked([ PAYMENT.merge("instructedAmount" => { "currency" => "XYZ", "amount" => "1" }) ])
        assert_equal "invalid_authorization_details", redirected["error"]
        assert_match "currency must be one of EUR, USD", redirected["error_description"]

        asked([ PAYMENT.merge("smuggled" => true) ])
        assert_match "does not accept smuggled", redirected["error_description"]
      end

      test "malformed details are refused" do
        asked({ "type" => TYPE })

        assert_equal "invalid_authorization_details", redirected["error"]
      end

      test "the token request may narrow the details, and never widen them" do
        other = PAYMENT.merge("creditorName" => "Merchant B")
        asked([ PAYMENT, other ])
        consent!
        code = code_from

        body = token(grant_type: "authorization_code", code: code, redirect_uri: OidcFlow::REDIRECT_URI,
                     code_verifier: verifier, client_id: @registration["client_id"],
                     client_secret: @registration["client_secret"], authorization_details: [ other ].to_json)

        assert_equal [ other ], body["authorization_details"]

        refreshed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                          client_id: @registration["client_id"], client_secret: @registration["client_secret"],
                          authorization_details: [ PAYMENT.merge("creditorName" => "Merchant C") ].to_json)

        assert_equal "invalid_authorization_details", refreshed["error"]
      end

      test "a refreshed token keeps the details that were granted" do
        body = granted

        refreshed = token(grant_type: "refresh_token", refresh_token: body["refresh_token"],
                          client_id: @registration["client_id"], client_secret: @registration["client_secret"])

        assert_equal [ PAYMENT ], refreshed["authorization_details"]
      end

      test "an exchange carries the details and cannot widen them" do
        subject = granted["access_token"]
        exchanged = lambda do |**params|
          token(grant_type: Exchange::GRANT_TYPE, subject_token: subject, subject_token_type: Exchange::ACCESS_TOKEN,
                client_id: @registration["client_id"], client_secret: @registration["client_secret"], **params)
        end

        assert_equal [ PAYMENT ], exchanged.call["authorization_details"]

        widened = exchanged.call(authorization_details: [ PAYMENT.merge("creditorName" => "Other") ].to_json)
        assert_equal "invalid_authorization_details", widened["error"]
      end

      test "a pushed request carries details, and a bad one is refused at the push" do
        sign_in_as(@actor)
        pushed = lambda do |details|
          post "/par", params: {
            response_type: "code", client_id: @registration["client_id"], client_secret: @registration["client_secret"],
            redirect_uri: OidcFlow::REDIRECT_URI, scope: "openid", code_challenge: challenge, code_challenge_method: "S256",
            authorization_details: details.to_json
          }
          JSON.parse(response.body)
        end

        assert_equal "invalid_authorization_details", pushed.call([ { "type" => "nobody" } ])["error"]

        get "/authorize", params: { client_id: @registration["client_id"], request_uri: pushed.call([ PAYMENT ])["request_uri"] }

        assert_equal "Send a payment", auth_data.dig("consent", "details", 0, "label")
      end

      def remembering(seconds)
        within { Client.find_by(name: "Bank").update!(authorization_details_schemas: { TYPE => { "label" => "Send a payment", "schema" => SCHEMA, "remember" => seconds } }) }
      end

      test "a type declared to be remembered is not asked about again until it expires" do
        remembering(1.day.to_i)
        granted

        asked
        assert_not awaiting_consent?, "the same details were allowed a moment ago"

        asked([ PAYMENT.merge("creditorName" => "Merchant B") ])
        assert awaiting_consent?, "different details are asked about"

        travel 25.hours do
          asked
          assert awaiting_consent?, "a remembered detail expires"
        end
      end

      test "remembered details are listed on the consent, and revoking the app forgets them" do
        remembering(1.day.to_i)
        granted

        consent = within { Consent.live.find_by(client: Client.find_by(client_id: @registration["client_id"])) }
        assert_equal [ PAYMENT ], consent.remembered

        get "/"
        assert_match "Send a payment, without asking until", response.body

        within { consent.revoke! }
        asked
        assert awaiting_consent?
      end

      test "a client that skips consent still asks about details nobody remembered" do
        within { Client.find_by(client_id: @registration["client_id"]).update!(approved_at: Time.current, consent_required: false) }

        asked

        assert awaiting_consent?
      end

      test "a declaration remembers for at most 400 days" do
        assert_raises(AuthorizationDetails::Invalid) do
          AuthorizationDetails.check_declaration!(TYPE => { "label" => "Pay", "schema" => SCHEMA, "remember" => 401.days.to_i })
        end
      end

      test "only an approved client may declare a type" do
        client = within { Client.new(name: "Unapproved", client_id: SecureRandom.uuid, redirect_uris: [ OidcFlow::REDIRECT_URI ]) }
        client.authorization_details_schemas = { TYPE => { "label" => "Pay", "schema" => SCHEMA } }

        within { assert_not client.valid? }
        assert_includes client.errors[:authorization_details_schemas], "may only be declared by an approved client"
      end
    end
  end
end
