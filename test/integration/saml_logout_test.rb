module Masks
  module Server
    require "test_helper"
    require_relative "../support/saml_idp"

    class SamlLogoutTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      SP = "https://sp.example.com/saml".freeze
      ACS = "https://sp.example.com/saml/acs".freeze
      SLO = "https://sp.example.com/saml/slo".freeze
      OTHER = "https://crm.example.com/saml".freeze
      OTHER_ACS = "https://crm.example.com/saml/acs".freeze
      OTHER_SLO = "https://crm.example.com/saml/slo".freeze

      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada", email: "ada@example.com", name: "Ada Lovelace", email_verified_at: Time.current)
        @key = OpenSSL::PKey::RSA.generate(2048)
        @certificate = SamlIdp.certificate_for(@key, name: "sp.example.com")
        @application = application(SP, ACS, SLO)
      end

      def application(entity, acs, slo, **attributes)
        within do
          Client.create!(
            client_id: SecureRandom.uuid, name: entity.split("/")[2], protocol: SamlIdentity::PROTOCOL,
            saml_entity_id: entity, redirect_uris: [ acs ], saml_slo_url: slo, saml_certificate: @certificate.to_pem,
            grant_types: [], response_types: [], token_endpoint_auth_method: "none",
            allowed_scopes: "openid profile email", approved_at: Time.current, consent_required: false, **attributes
          )
        end
      end

      def origin
        origin_for(@tenant)
      end

      def idp_certificate
        within { SigningKey.active.first.certificate }
      end

      def settings(entity: SP, acs: ACS, slo: SLO, key: @key, certificate: @certificate, post: false, signed: true)
        OneLogin::RubySaml::Settings.new.tap do |held|
          held.sp_entity_id = entity
          held.assertion_consumer_service_url = acs
          held.single_logout_service_url = slo
          held.idp_entity_id = "#{origin}/saml/metadata"
          held.idp_sso_service_url = "#{origin}/saml/sso"
          held.idp_slo_service_url = "#{origin}/saml/slo"
          held.idp_slo_service_binding = post ? SamlIdentity::POST_BINDING : SamlIdentity::REDIRECT_BINDING
          held.idp_cert = idp_certificate.to_pem
          held.name_identifier_format = SamlIdentity::PERSISTENT
          held.certificate = certificate.to_pem
          held.private_key = key.to_pem
          held.security[:want_assertions_signed] = true
          held.security[:logout_requests_signed] = signed
          held.security[:logout_responses_signed] = signed
          held.security[:digest_method] = XMLSecurity::Document::SHA256
          held.security[:signature_method] = XMLSecurity::Document::RSA_SHA256
        end
      end

      def form
        held = Nokogiri::HTML(response.body).at_css("form#saml-message")

        assert held, "nothing was posted: #{response.body[0, 400]}"

        [ held["action"], held.css("input").to_h { |input| [ input["name"], input["value"] ] } ]
      end

      def signed_in_to(held = settings)
        request = OneLogin::RubySaml::Authrequest.new
        get request.create(held).delete_prefix(origin)

        _, fields = form
        saml = OneLogin::RubySaml::Response.new(fields["SAMLResponse"], settings: held, matches_request_id: request.request_id)

        assert saml.is_valid?(true), saml.errors.join("; ")
        saml
      end

      def logout_request(held, name_id:, session_index:)
        held.name_identifier_value = name_id
        held.sessionindex = session_index

        OneLogin::RubySaml::Logoutrequest.new
      end

      def answered(held, request, success: true)
        destination, fields = form

        assert_equal held.single_logout_service_url, destination

        reply = OneLogin::RubySaml::Logoutresponse.new(fields["SAMLResponse"], held, matches_request_id: request.uuid)

        assert reply.validate(true), reply.errors.join("; ") if success
        assert_equal request.uuid, reply.in_response_to
        assert_equal held.idp_entity_id, reply.issuer
        assert XMLSecurity::SignedDocument.new(Base64.decode64(fields["SAMLResponse"])).validate_document_with_cert(idp_certificate, true)

        [ reply, fields ]
      end

      def asked_to_leave(held)
        destination, fields = form

        assert_equal held.single_logout_service_url, destination

        request = OneLogin::RubySaml::SloLogoutrequest.new(fields["SAMLRequest"], settings: held)

        assert request.is_valid?(true), request.errors.join("; ")
        assert XMLSecurity::SignedDocument.new(Base64.decode64(fields["SAMLRequest"])).validate_document_with_cert(idp_certificate, true)

        request
      end

      def leave(held, request)
        held.idp_slo_service_binding = SamlIdentity::POST_BINDING

        post "/saml/slo", params: OneLogin::RubySaml::SloLogoutresponse.new.create_params(held, request.id)
      end

      def live_sessions
        within { Session.live.where(actor: @actor).count }
      end

      test "an application signs a person out over the redirect binding and is answered" do
        sign_in_as(@actor)
        saml = signed_in_to
        held = settings
        request = logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex)

        get request.create(held, RelayState: "after-logout").delete_prefix(origin)

        reply, fields = answered(held, request)

        assert reply.success?
        assert_equal "after-logout", fields["RelayState"]
        assert_equal 0, live_sessions
        assert_empty cookies[:masks_session].to_s
      end

      test "an application signs a person out over the POST binding and is answered" do
        sign_in_as(@actor)
        saml = signed_in_to
        held = settings(post: true)
        request = logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex)

        post "/saml/slo", params: request.create_params(held, RelayState: "after-logout")

        reply, = answered(held, request)

        assert reply.success?
        assert_equal 0, live_sessions
      end

      test "a LogoutRequest is refused unless the application signed it with its own key" do
        sign_in_as(@actor)
        saml = signed_in_to

        unsigned = settings(signed: false)
        get logout_request(unsigned, name_id: saml.name_id, session_index: saml.sessionindex).create(unsigned).delete_prefix(origin)

        assert_response :bad_request
        assert_match "SigAlg", response.body

        impostor = OpenSSL::PKey::RSA.generate(2048)
        forged = settings(key: impostor, certificate: SamlIdp.certificate_for(impostor), post: true)
        post "/saml/slo", params: logout_request(forged, name_id: saml.name_id, session_index: saml.sessionindex).create_params(forged)

        assert_response :bad_request
        assert_match "does not verify", response.body
        assert_equal 1, live_sessions
      end

      test "an application with no certificate cannot sign anybody out" do
        within { @application.update!(saml_certificate: nil) }
        sign_in_as(@actor)
        saml = signed_in_to
        held = settings

        get logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex).create(held).delete_prefix(origin)

        assert_response :bad_request
        assert_match "no certificate", response.body
        assert_equal 1, live_sessions
      end

      test "a LogoutRequest naming somebody else is refused, and the session stays" do
        sign_in_as(@actor)
        saml = signed_in_to
        held = settings
        request = logout_request(held, name_id: SecureRandom.uuid, session_index: saml.sessionindex)

        get request.create(held).delete_prefix(origin)

        reply, = answered(held, request, success: false)

        refute reply.success?
        assert_equal SamlIdentity::REQUESTER, reply.status_code
        assert_equal 1, live_sessions
      end

      test "the same LogoutRequest is answered once" do
        sign_in_as(@actor)
        saml = signed_in_to
        held = settings
        location = logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex).create(held).delete_prefix(origin)

        get location
        assert_response :success

        get location
        assert_response :bad_request
        assert_match "already been answered", response.body
      end

      test "an application ending the session leads the browser through the other applications first" do
        other = settings(entity: OTHER, acs: OTHER_ACS, slo: OTHER_SLO)
        application(OTHER, OTHER_ACS, OTHER_SLO)

        sign_in_as(@actor)
        saml = signed_in_to
        signed_in_to(other)

        held = settings
        request = logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex)

        assert_no_enqueued_jobs(only: SamlLogoutJob) { get request.create(held).delete_prefix(origin) }

        leave(other, asked_to_leave(other))

        reply, = answered(settings, request)

        assert reply.success?
        assert_equal 0, live_sessions
      end

      test "an application ending a session this browser does not hold tells the other applications from the server" do
        other = settings(entity: OTHER, acs: OTHER_ACS, slo: OTHER_SLO)
        application(OTHER, OTHER_ACS, OTHER_SLO)

        sign_in_as(@actor)
        saml = signed_in_to
        signed_in_to(other)
        reset!
        host! host_for(@tenant)

        held = settings(post: true)
        request = logout_request(held, name_id: saml.name_id, session_index: saml.sessionindex)

        assert_enqueued_jobs(1, only: SamlLogoutJob) { post "/saml/slo", params: request.create_params(held) }

        reply, = answered(held, request)

        assert reply.success?
        assert_equal 0, live_sessions
        assert within { Event.where(action: Event::SESSION_ENDED, actor: @actor, client: @application, by: nil).exists? }
      end

      test "signing out of masks leads the browser through every application with a logout URL" do
        other = settings(entity: OTHER, acs: OTHER_ACS, slo: OTHER_SLO)
        application(OTHER, OTHER_ACS, OTHER_SLO)
        silent = settings(entity: "https://silent.example.com/saml", acs: "https://silent.example.com/acs")
        application("https://silent.example.com/saml", "https://silent.example.com/acs", nil)

        sign_in_as(@actor)
        saml = signed_in_to
        signed_in_to(other)
        signed_in_to(silent)

        assert_no_enqueued_jobs(only: SamlLogoutJob) { post "/logout" }
        assert_equal 0, live_sessions

        first = asked_to_leave(settings)

        assert_equal saml.name_id, first.name_id
        assert_equal [ saml.sessionindex ], first.session_indexes

        leave(settings, first)
        leave(other, asked_to_leave(other))

        assert_redirected_to "/login"

        leave(other, first)

        assert_response :bad_request
      end

      test "a session ended without a browser is posted to each application's logout URL" do
        sign_in_as(@actor)
        saml = signed_in_to

        delivered = []
        stub_request(:post, SLO).to_return do |request|
          delivered << Rack::Utils.parse_query(request.body)["SAMLRequest"]
          { status: 200 }
        end

        perform_enqueued_jobs { within { @actor.sign_out_everywhere! } }

        assert_equal 1, delivered.size

        request = OneLogin::RubySaml::SloLogoutrequest.new(delivered.first, settings: settings(post: true))

        assert request.is_valid?(true), request.errors.join("; ")
        assert XMLSecurity::SignedDocument.new(Base64.decode64(delivered.first)).validate_document_with_cert(idp_certificate, true)
        assert_equal saml.name_id, request.name_id
        assert_equal [ saml.sessionindex ], request.session_indexes

        perform_enqueued_jobs { within { @actor.sign_out_everywhere! } }

        assert_equal 1, delivered.size
      end

      test "the metadata advertises single logout over both bindings" do
        get "/saml/metadata"

        services = Nokogiri::XML(response.body).xpath("//md:SingleLogoutService", "md" => SamlIdentity::METADATA_NS)

        assert_equal [ SamlIdentity::REDIRECT_BINDING, SamlIdentity::POST_BINDING ], services.map { |service| service["Binding"] }
        assert_equal [ "#{origin}/saml/slo" ], services.map { |service| service["Location"] }.uniq
      end

      test "a logout URL masks would not post to is refused" do
        error = assert_raises(ActiveRecord::RecordInvalid) { within { @application.update!(saml_slo_url: "ftp://sp.example.com/slo") } }

        assert_match "Saml slo url", error.message
      end
    end
  end
end
