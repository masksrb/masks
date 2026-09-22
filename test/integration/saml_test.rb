module Masks
  module Server
    require "test_helper"
    require_relative "../support/saml_idp"

    class SamlTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @idp = SamlIdp.new
        create_actor(@tenant, nickname: "owner", email: "owner@acme.test")
      end

      def saml_provider!(**attributes)
        within(@tenant) do
          Provider.create!(
            key: "acme", name: "Acme", protocol: "saml", role: "delegate", email_domains: "acme.test",
            **Federation::Saml.parse_metadata(@idp.metadata),
            claims: { "email" => "email", "name" => "displayName" },
            **attributes
          )
        end
      end

      def callback
        "#{origin_for(@tenant)}/login/provider/acme/callback"
      end

      def audience
        "#{origin_for(@tenant)}/login/provider/acme/metadata"
      end

      def begin_saml(rid: nil)
        post "/login", params: { event: "provider", provider: "acme", rid: rid }.compact, as: :json

        location = JSON.parse(response.body)["redirectTo"]
        query = Rack::Utils.parse_query(URI.parse(location).query)
        inflated = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query["SAMLRequest"]))

        { "location" => location, "relay" => query["RelayState"], "request_id" => inflated[/ID=['"]([^'"]+)['"]/, 1] }
      end

      def answer(handoff, **overrides)
        saml_response = @idp.response(
          **{ in_response_to: handoff["request_id"], destination: callback, audience: audience,
              name_id: "okta-00u1", attributes: { "email" => "grace@acme.test", "displayName" => "Grace Hopper" } }
            .merge(overrides)
        )

        post "/login/provider/acme/callback", params: { SAMLResponse: saml_response, RelayState: handoff["relay"] }
        follow_redirect! if response.status == 303
      end

      def signed_in_actor
        within(@tenant) { Session.live.order(created_at: :desc).first&.actor }
      end

      def refusals
        within(@tenant) { Event.where(action: Event::CONNECTION_REFUSED).map { |event| event.details["reason"].to_s } }
      end

      test "a saml identity provider signs somebody in with a signed assertion" do
        saml_provider!

        handoff = begin_saml

        assert handoff["location"].start_with?(@idp.sso_url)
        assert handoff["request_id"].present?

        answer(handoff)

        actor = signed_in_actor

        assert actor, refusals.join("; ")
        assert_equal "grace@acme.test", actor.email
        assert_equal "Grace Hopper", actor.name
        assert_equal "okta-00u1", within(@tenant) { Connection.live.find_by(actor: actor).subject }
      end

      test "an unsigned assertion is refused" do
        saml_provider!

        answer(begin_saml, sign: false)

        assert_nil signed_in_actor
        assert_match(/could not trust/, refusals.join)
      end

      test "an assertion signed by a key the provider does not publish is refused" do
        saml_provider!
        stranger = OpenSSL::PKey::RSA.generate(2048)

        answer(begin_saml, signer: stranger, signed_certificate: SamlIdp.certificate_for(stranger))

        assert_nil signed_in_actor
      end

      test "an assertion altered after it was signed is refused" do
        saml_provider!

        handoff = begin_saml
        signed = Base64.decode64(@idp.response(
          in_response_to: handoff["request_id"], destination: callback, audience: audience,
          name_id: "okta-00u1", attributes: { "email" => "grace@acme.test" }
        ))

        tampered = Base64.strict_encode64(signed.sub("okta-00u1", "okta-admin").sub("grace@acme.test", "owner@acme.test"))

        post "/login/provider/acme/callback", params: { SAMLResponse: tampered, RelayState: handoff["relay"] }
        follow_redirect!

        assert_nil signed_in_actor
        assert_nil within(@tenant) { Connection.find_by(subject: "okta-admin") }
      end

      test "an assertion answering another request is refused" do
        saml_provider!

        answer(begin_saml, in_response_to: "_somebody-elses-request")

        assert_nil signed_in_actor
      end

      test "an assertion nobody asked for is refused" do
        saml_provider!

        answer(begin_saml, in_response_to: nil)

        assert_nil signed_in_actor
      end

      test "an assertion meant for another service is refused" do
        saml_provider!

        answer(begin_saml, audience: "https://elsewhere.test/metadata")

        assert_nil signed_in_actor
      end

      test "an assertion from another identity provider is refused" do
        saml_provider!

        answer(begin_saml, issuer: "https://idp.evil.test/saml")

        assert_nil signed_in_actor
      end

      test "an expired assertion is refused" do
        saml_provider!

        handoff = begin_saml
        saml_response = @idp.response(
          in_response_to: handoff["request_id"], destination: callback, audience: audience,
          name_id: "okta-00u1", attributes: { "email" => "grace@acme.test" }
        )

        travel 10.minutes

        post "/login/provider/acme/callback", params: { SAMLResponse: saml_response, RelayState: handoff["relay"] }
        follow_redirect!

        assert_nil signed_in_actor
      end

      test "the same assertion does not sign anybody in twice" do
        saml_provider!

        handoff = begin_saml
        saml_response = @idp.response(
          in_response_to: handoff["request_id"], destination: callback, audience: audience,
          name_id: "okta-00u1", attributes: { "email" => "grace@acme.test" }
        )

        post "/login/provider/acme/callback", params: { SAMLResponse: saml_response, RelayState: handoff["relay"] }
        follow_redirect!

        assert signed_in_actor

        within(@tenant) { Session.live.find_each(&:revoke!) }
        reset!
        host! host_for(@tenant)

        post "/login/provider/acme/callback", params: { SAMLResponse: saml_response, RelayState: handoff["relay"] }
        follow_redirect!

        assert_nil signed_in_actor
      end

      test "an address outside the provider's domains is not confirmed by saml" do
        saml_provider!(email_domains: "")

        answer(begin_saml)

        assert_nil signed_in_actor
      end

      test "the service provider metadata names the entity and where assertions go" do
        saml_provider!

        get "/login/provider/acme/metadata"

        assert_response :success
        assert_match(/entityID=['"]#{Regexp.escape(audience)}['"]/, response.body)
        assert_includes response.body, callback
      end

      test "metadata that names no certificate is refused" do
        within(@tenant) do
          provider = Provider.new(key: "bare", name: "Bare", protocol: "saml", idp_entity_id: "x",
                                  idp_sso_url: "https://idp.acme.test/sso", idp_certificates: "not a certificate")

          assert_not provider.valid?
          assert provider.errors[:idp_certificates].any?
        end
      end
    end
  end
end
