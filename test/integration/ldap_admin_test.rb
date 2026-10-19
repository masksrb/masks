module Masks
  module Server
    require "test_helper"

    class LdapAdminTest < ActionDispatch::IntegrationTest
      ROLES = Scopes.join(ManageRoles::SCOPES)

      setup do
        host! host_for(@tenant)

        @owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        @console = create_client(@tenant, name: "Console", allowed_scopes: "openid profile email #{ROLES}",
                                          approved_at: Time.current, grant_types: [ "authorization_code" ])
      end

      def bearer_for(actor)
        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: @console.client_id, scope: "openid #{ROLES}", resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: @console.client_id)["access_token"]
      end

      def ask(query, actor: @owner, **variables)
        @bearers ||= {}
        @bearers[actor.id] ||= bearer_for(actor)

        manage(query, bearer: @bearers[actor.id], **variables)
      end

      test "an owner issues an LDAP credential, sees it listed, and revokes it" do
        issued = ask('mutation { issueLdapCredential(label: "Jellyfin") { secret ldapCredential { id label bindDn } } }')
          .dig("data", "issueLdapCredential")

        base = "dc=#{@tenant.subdomain},dc=masks"
        assert issued["secret"].present?
        assert_equal "jellyfin", issued.dig("ldapCredential", "label")
        assert_equal "cn=jellyfin,ou=services,#{base}", issued.dig("ldapCredential", "bindDn")

        listed = ask("{ ldapBaseDn ldapCredentials { label issuedBy { identifier } } }")["data"]
        assert_equal base, listed["ldapBaseDn"]
        assert_equal [ "jellyfin" ], listed["ldapCredentials"].map { |credential| credential["label"] }
        assert_equal "owner", listed["ldapCredentials"].first.dig("issuedBy", "identifier")

        stored = within { LdapCredential.find(issued.dig("ldapCredential", "id")) }
        assert_not_equal issued["secret"], stored.digest
        assert_not_includes stored.payload.to_json, issued["secret"]

        ask("mutation($id: ID!) { revokeLdapCredential(id: $id) { ldapCredential { id } } }", id: issued.dig("ldapCredential", "id"))

        assert_empty ask("{ ldapCredentials { id } }").dig("data", "ldapCredentials")
        assert_nil within { LdapCredential.check("jellyfin", issued["secret"]) }
        assert within { Event.exists?(action: Event::LDAP_CREDENTIAL_REVOKED) }
      end

      test "labels are checked and stay unique while live" do
        ask('mutation { issueLdapCredential(label: "nas") { secret } }')

        body = ask('mutation { issueLdapCredential(label: "nas") { secret } }')
        assert_match "already labeled nas", body["errors"].first["message"]

        body = ask('mutation { issueLdapCredential(label: "a b,c") { secret } }')
        assert_match "lowercase letters", body["errors"].first["message"]
      end

      test "an owner turns the LDAP directory on and off" do
        facts = ask("{ tenant { ldapEnabled } ldapPort ldapTls ldapLocalOnly }")["data"]

        assert_equal false, facts.dig("tenant", "ldapEnabled")
        assert_equal false, facts["ldapTls"]
        assert_equal true, facts["ldapLocalOnly"]

        ask("mutation { updateTenant(ldapEnabled: true) { tenant { ldapEnabled } } }")
        assert @tenant.reload.ldap?
        assert_equal [ @tenant ], Tenant.ldap.to_a

        ask("mutation { updateTenant(ldapEnabled: false) { tenant { ldapEnabled } } }")
        assert_not @tenant.reload.ldap?
      end

      test "an owner allows a password alone over LDAP" do
        assert_equal false, ask("{ tenant { ldapPasswordOnly } }").dig("data", "tenant", "ldapPasswordOnly")

        ask("mutation { updateTenant(ldapPasswordOnly: true) { tenant { ldapPasswordOnly } } }")

        assert @tenant.reload.ldap_password_only?
      end

      test "only an owner issues LDAP credentials" do
        support = create_actor(@tenant, nickname: "support", scopes: "openid profile email #{ManageRoles::SUPPORT}")

        body = ask('mutation { issueLdapCredential(label: "nas") { secret } }', actor: support)

        assert body["errors"].present?
        assert_empty within { LdapCredential.live.to_a }
      end
    end
  end
end
