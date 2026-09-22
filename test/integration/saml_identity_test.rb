module Masks
  module Server
    require "test_helper"
    require_relative "../support/saml_idp"

    class SamlIdentityTest < ActionDispatch::IntegrationTest
      SP = "https://sp.example.com/saml".freeze
      ACS = "https://sp.example.com/saml/acs".freeze

      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada", email: "ada@example.com", name: "Ada Lovelace", given_name: "Ada",
                              email_verified_at: Time.current)
        @application = application
      end

      def application(**attributes)
        within do
          Client.create!(
            client_id: SecureRandom.uuid, name: "Wiki", protocol: SamlIdentity::PROTOCOL,
            saml_entity_id: SP, redirect_uris: [ ACS ], grant_types: [], response_types: [],
            token_endpoint_auth_method: "none", allowed_scopes: "openid profile email",
            approved_at: Time.current, consent_required: false, **attributes
          )
        end
      end

      def idp_certificate
        within { SigningKey.active.first.certificate }
      end

      def settings(**overrides)
        OneLogin::RubySaml::Settings.new.tap do |held|
          held.sp_entity_id = SP
          held.assertion_consumer_service_url = ACS
          held.idp_entity_id = "#{origin_for(@tenant)}/saml/metadata"
          held.idp_sso_service_url = "#{origin_for(@tenant)}/saml/sso"
          held.idp_cert = idp_certificate.to_pem
          held.name_identifier_format = SamlIdentity::PERSISTENT
          held.security[:want_assertions_signed] = true
          held.security[:digest_method] = XMLSecurity::Document::SHA256
          held.security[:signature_method] = XMLSecurity::Document::RSA_SHA256
          overrides.each { |key, value| held.public_send(:"#{key}=", value) }
        end
      end

      def start(held = settings, relay: "back-to-page")
        request = OneLogin::RubySaml::Authrequest.new
        location = request.create(held, RelayState: relay)

        get location.delete_prefix(origin_for(@tenant))

        request
      end

      def posted
        form = Nokogiri::HTML(response.body).at_css("form#saml-response")

        assert form, "no SAML response was posted: #{response.body[0, 400]}"
        assert_equal ACS, form["action"]

        form.css("input").to_h { |input| [ input["name"], input["value"] ] }
      end

      def validated(request, held = settings)
        saml = OneLogin::RubySaml::Response.new(posted["SAMLResponse"], settings: held, matches_request_id: request&.request_id)

        assert saml.is_valid?(true), saml.errors.join("; ")
        saml
      end

      test "a signed-in person is posted back to the application with an assertion it trusts" do
        sign_in_as(@actor)
        request = start

        saml = validated(request)

        assert_equal @actor.uuid, saml.name_id
        assert_equal "ada@example.com", saml.attributes["email"]
        assert_equal "Ada Lovelace", saml.attributes["name"]
        assert_equal "back-to-page", posted["RelayState"]
        assert_match "script-src 'nonce-", response.headers["Content-Security-Policy"]
        assert within { Event.where(action: Event::SAML_ASSERTED, actor: @actor).exists? }
      end

      test "somebody not signed in is asked to, and the application hears back after" do
        request = start

        assert_equal "identify", auth_data["prompt"]

        advance!("identify", identifier: "ada")
        advance!("password", password: "password")

        validated(request)
      end

      test "the NameID can be the person's email" do
        sign_in_as(@actor)
        request = start(settings(name_identifier_format: SamlIdentity::EMAIL))

        assert_equal "ada@example.com", validated(request, settings(name_identifier_format: SamlIdentity::EMAIL)).name_id
      end

      test "an application nobody registered is refused before anybody signs in" do
        start(settings(sp_entity_id: "https://stranger.example.com/saml"))

        assert_response :bad_request
        assert_match "no application is registered", response.body
      end

      test "an assertion consumer service the application never registered is refused" do
        start(settings(assertion_consumer_service_url: "https://evil.example.com/acs"))

        assert_response :bad_request
        assert_match "not an assertion consumer service", response.body
      end

      test "the same AuthnRequest is answered once" do
        sign_in_as(@actor)
        request = OneLogin::RubySaml::Authrequest.new
        location = request.create(settings).delete_prefix(origin_for(@tenant))

        get location
        assert posted["SAMLResponse"]

        get location
        assert_response :bad_request
      end

      test "an application that signs its requests is refused an unsigned one, and answered a signed one" do
        key = OpenSSL::PKey::RSA.generate(2048)
        certificate = SamlIdp.certificate_for(key, name: "sp.example.com")
        within { @application.update!(saml_requests_signed: true, saml_certificate: certificate.to_pem) }

        start
        assert_response :bad_request

        signing = settings(certificate: certificate.to_pem, private_key: key.to_pem)
        signing.security[:authn_requests_signed] = true

        sign_in_as(@actor)
        validated(start(signing))
      end

      test "a request posted with its signature inside the XML is answered" do
        key = OpenSSL::PKey::RSA.generate(2048)
        certificate = SamlIdp.certificate_for(key, name: "sp.example.com")
        within { @application.update!(saml_requests_signed: true, saml_certificate: certificate.to_pem) }

        signing = settings(certificate: certificate.to_pem, private_key: key.to_pem)
        signing.idp_sso_service_binding = SamlIdentity::POST_BINDING
        signing.compress_request = false
        signing.security[:authn_requests_signed] = true

        request = OneLogin::RubySaml::Authrequest.new
        params = request.create_params(signing)

        sign_in_as(@actor)
        post "/saml/sso", params: { "SAMLRequest" => params["SAMLRequest"] }

        validated(request)

        tampered = Base64.strict_encode64(Base64.decode64(params["SAMLRequest"]).sub(ACS, "https://evil.example.com/acs"))
        post "/saml/sso", params: { "SAMLRequest" => tampered }

        assert_response :bad_request

        xml = Base64.decode64(request.create_params(signing)["SAMLRequest"])
        wrapped = xml.sub("</samlp:AuthnRequest>", %(<samlp:Extensions><samlp:AuthnRequest ID="#{xml[/ID=['"]([^'"]+)/, 1]}"/></samlp:Extensions></samlp:AuthnRequest>))
        post "/saml/sso", params: { "SAMLRequest" => Base64.strict_encode64(wrapped) }

        assert_response :bad_request
        assert_match "each ID once", response.body
      end

      test "an email nobody confirmed is never asserted" do
        within { @actor.update!(email_verified_at: nil) }
        sign_in_as(@actor)

        saml = validated(start)

        assert_nil saml.attributes["email"]
        assert_equal "Ada Lovelace", saml.attributes["name"]

        start(settings(name_identifier_format: SamlIdentity::EMAIL))

        assert_response :bad_request
        assert_match "no confirmed email", response.body
      end

      test "a second SAMLRequest smuggled beside a signed one is refused" do
        key = OpenSSL::PKey::RSA.generate(2048)
        certificate = SamlIdp.certificate_for(key, name: "sp.example.com")
        within { @application.update!(saml_requests_signed: true, saml_certificate: certificate.to_pem) }

        signing = settings(certificate: certificate.to_pem, private_key: key.to_pem)
        signing.security[:authn_requests_signed] = true
        genuine = OneLogin::RubySaml::Authrequest.new.create(signing).delete_prefix(origin_for(@tenant))
        forged = OneLogin::RubySaml::Authrequest.new.create(settings(assertion_consumer_service_url: ACS))
        smuggled = URI.decode_www_form(URI.parse(forged).query).to_h["SAMLRequest"]

        sign_in_as(@actor)
        get "#{genuine}&SAML%52equest=#{CGI.escape(smuggled)}"

        assert_response :bad_request
        assert_match "more than once", response.body
      end

      test "a genuine signature wrapped inside a forged request is refused" do
        key = OpenSSL::PKey::RSA.generate(2048)
        certificate = SamlIdp.certificate_for(key, name: "sp.example.com")
        within { @application.update!(saml_requests_signed: true, saml_certificate: certificate.to_pem) }

        signing = settings(certificate: certificate.to_pem, private_key: key.to_pem)
        signing.idp_sso_service_binding = SamlIdentity::POST_BINDING
        signing.compress_request = false
        signing.security[:authn_requests_signed] = true

        genuine = Base64.decode64(OneLogin::RubySaml::Authrequest.new.create_params(signing)["SAMLRequest"]).sub(/\A<\?xml[^>]*\?>/, "")
        outer = Base64.decode64(OneLogin::RubySaml::Authrequest.new.create_params(signing)["SAMLRequest"])
        forged = outer.sub("<samlp:NameIDPolicy", "<samlp:Extensions>#{genuine}</samlp:Extensions><samlp:NameIDPolicy")

        sign_in_as(@actor)
        post "/saml/sso", params: { "SAMLRequest" => Base64.strict_encode64(forged) }

        assert_response :bad_request
      end

      test "a request that inflates past the limit is refused without inflating all of it" do
        bomb = Base64.strict_encode64(Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS).then { |z| z.deflate("<" + ("a" * 5.megabytes), Zlib::FINISH) })

        get "/saml/sso?SAMLRequest=#{CGI.escape(bomb)}"

        assert_response :bad_request
        assert_match "too large", response.body
      end

      test "a signed request made with another key is refused" do
        key = OpenSSL::PKey::RSA.generate(2048)
        certificate = SamlIdp.certificate_for(key, name: "sp.example.com")
        within { @application.update!(saml_requests_signed: true, saml_certificate: certificate.to_pem) }

        impostor = OpenSSL::PKey::RSA.generate(2048)
        signing = settings(certificate: SamlIdp.certificate_for(impostor).to_pem, private_key: impostor.to_pem)
        signing.security[:authn_requests_signed] = true

        start(signing)

        assert_response :bad_request
        assert_match "does not verify", response.body
      end

      test "a suspended person is refused, and the application is told so" do
        sign_in_as(@actor)
        within { @actor.suspend! }
        request = start

        advance!("identify", identifier: "ada")
        advance!("password", password: "password")

        saml = OneLogin::RubySaml::Response.new(posted["SAMLResponse"], settings: settings, matches_request_id: request.request_id)

        refute saml.success?
        assert_match "RequestDenied", saml.status_code
      end

      test "a passive request with nobody signed in answers NoPassive" do
        request = OneLogin::RubySaml::Authrequest.new
        held = settings
        held.passive = true

        get request.create(held).delete_prefix(origin_for(@tenant))

        saml = OneLogin::RubySaml::Response.new(posted["SAMLResponse"], settings: held, matches_request_id: request.request_id)

        refute saml.success?
        assert_match "NoPassive", saml.status_code
      end

      test "an application can be signed into from masks only when it allows it" do
        sign_in_as(@actor)

        get "/saml/initiate/#{@application.client_id}"
        assert_response :bad_request

        within { @application.update!(saml_idp_initiated: true) }

        get "/saml/initiate/#{@application.client_id}"
        saml = OneLogin::RubySaml::Response.new(posted["SAMLResponse"], settings: settings)

        assert saml.is_valid?(true), saml.errors.join("; ")
        assert_nil saml.in_response_to
      end

      test "the metadata names the entity, both bindings and the signing certificate" do
        get "/saml/metadata"

        document = Nokogiri::XML(response.body)
        names = { "md" => SamlIdentity::METADATA_NS, "ds" => SamlIdentity::DSIG_NS }

        assert_equal "#{origin_for(@tenant)}/saml/metadata", document.root["entityID"]
        assert_equal 2, document.xpath("//md:SingleSignOnService", names).size
        assert_equal Base64.strict_encode64(idp_certificate.to_der), document.at_xpath("//ds:X509Certificate", names).text
        assert_equal idp_certificate.to_pem, within { SigningKey.active.first.reload.certificate.to_pem }
      end

      test "a SAML application cannot be used as an OAuth client" do
        authorize(client_id: @application.client_id)

        assert_response :bad_request
      end

      test "an application without an entity id, or with grants, is refused" do
        assert_raises(ActiveRecord::RecordInvalid) { application(saml_entity_id: nil) }
        assert_raises(ActiveRecord::RecordInvalid) { application(saml_entity_id: "https://other.example.com", grant_types: [ "authorization_code" ]) }
      end
    end
  end
end
