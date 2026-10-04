module Masks
  module Server
    require "test_helper"

    class CustomDomainsTest < ActionDispatch::IntegrationTest
      ROLES = Scopes.join(ManageRoles::SCOPES)
      HOST = "login.acme.example".freeze
      SERVE = %(mutation($host: String) { serveDomain(host: $host) { tenant { customHost origins } } }).freeze

      setup do
        host! host_for(@tenant)

        @owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        @client = create_client(
          @tenant,
          allowed_scopes: "openid profile email #{ROLES}",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def bearer_for(actor)
        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: @client.client_id, scope: "openid #{ROLES}", resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @client.client_id)["access_token"]
      end

      def ask(query, token, **variables)
        host! host_for(@tenant)
        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }

        JSON.parse(response.body)
      end

      def refusal(body)
        body["errors"]&.first&.dig("message")
      end

      def prove(domain = "acme.example", tenant = @tenant)
        Tenant.switch(tenant) { DomainClaim.create!(domain: domain).tap { |claim| claim.update_columns(verified_at: Time.current) } }
      end

      def with_origin(origin)
        was = ::Rails.configuration.masks.public_origin_template
        ::Rails.configuration.masks.public_origin_template = origin

        yield
      ensure
        ::Rails.configuration.masks.public_origin_template = was
      end

      def discovery_at(host)
        host! host
        get "/.well-known/openid-configuration"

        response.successful? ? JSON.parse(response.body) : nil
      end

      test "a host outside every proven domain is refused" do
        body = ask(SERVE, bearer_for(@owner), host: HOST)

        assert_match "within a domain this tenant has proven", refusal(body)
      end

      test "an owner serves sign-in from a host within a proven domain" do
        prove

        body = ask(SERVE, bearer_for(@owner), host: HOST.upcase)

        assert_equal HOST, body.dig("data", "serveDomain", "tenant", "customHost")
        assert_includes body.dig("data", "serveDomain", "tenant", "origins"), "https://#{HOST}"
        assert_equal "http://#{HOST}", discovery_at(HOST)["issuer"]
        assert within { Event.exists?(action: Event::CUSTOM_DOMAIN_SERVED) }
      end

      test "only an owner changes the served host" do
        prove
        security = create_actor(@tenant, nickname: "security", scopes: "openid profile email #{ManageRoles::SECURITY}")

        body = ask(SERVE, bearer_for(security), host: HOST)

        assert_match "masks:manage", refusal(body)
      end

      test "the served host answers under the template with its own https origin" do
        prove
        within { @tenant.update!(custom_host: HOST) }

        with_origin("https://%{subdomain}.auth.test") do
          assert_equal "https://#{HOST}", discovery_at(HOST)["issuer"]
          assert_equal "https://#{@tenant.subdomain}.auth.test", discovery_at(host_for(@tenant))["issuer"]
          assert_nil discovery_at("login.globex.example")
        end
      end

      test "a host within this server's own domain is refused" do
        prove("auth.test")

        with_origin("https://%{subdomain}.auth.test") do
          assert_equal "auth.test", Tenant.served_domain

          within { @tenant.custom_host = "other.auth.test" }

          assert_not within { @tenant.valid? }
          assert_includes @tenant.errors[:custom_host], "is part of this server's own domain"
        end
      end

      test "the certificate check allows only served hosts" do
        prove
        within { @tenant.update!(custom_host: HOST) }

        get "/tls/allowed", params: { domain: HOST }

        assert_response :ok

        get "/tls/allowed", params: { domain: "login.globex.example" }

        assert_response :not_found
      end

      test "releasing the domain stops serving the host" do
        prove
        within { @tenant.update!(custom_host: HOST) }

        ask(%(mutation { releaseDomain(domain: "acme.example") { domain } }), bearer_for(@owner))

        assert_nil @tenant.reload.custom_host
        assert within { Event.exists?(action: Event::CUSTOM_DOMAIN_STOPPED) }
        assert_nil Tenant.serving(HOST)
      end

      test "a lapsed proof stops serving the host" do
        claim = prove
        within { @tenant.update!(custom_host: HOST) }
        within { claim.update_columns(verified_at: nil) }

        CheckDomainClaimsJob.perform_now

        assert_nil @tenant.reload.custom_host
      end

      test "a host the server's own domain grew to cover stops being served" do
        prove
        within { @tenant.update!(custom_host: HOST) }

        with_origin("https://%{subdomain}.acme.example") do
          CheckDomainClaimsJob.perform_now
        end

        assert_nil @tenant.reload.custom_host
        assert within { Event.exists?(action: Event::CUSTOM_DOMAIN_STOPPED) }
      end

      test "stopping clears the host" do
        prove
        within { @tenant.update!(custom_host: HOST) }

        body = ask(SERVE, bearer_for(@owner), host: nil)

        assert_nil body.dig("data", "serveDomain", "tenant", "customHost")
        assert_nil @tenant.reload.custom_host
      end
    end
  end
end
