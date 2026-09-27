module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"

    class OrganizationRolesTest < ActionDispatch::IntegrationTest
      include Federated

      SCOPE = "openid profile email offline_access organization".freeze

      setup do
        @registration = register(scope: SCOPE)
        host! host_for(@tenant)
        @acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "admin" ]) }
        create_provider(role: "delegate", email_domains: "acme.test", organization: @acme,
                        role_map: { "Acme Owners" => "owner" })
        create_actor(nickname: "owner", email: "owner@acme.test")
      end

      def arrive(groups)
        reset!
        host! host_for(@tenant)
        authorize(client_id: @registration["client_id"], scope: SCOPE, organization: "acme")
        finish_sso(sub: "upstream-7", email: "grace@acme.test", groups: groups, handoff: begin_sso(rid: current_rid))
      end

      test "a provider that would demote an organization's last owner leaves the owner and says so" do
        arrive([ "Acme Owners" ])
        arrive([ "Everyone" ])

        assert_equal "owner", within { @acme.memberships.sole.role }

        kept = within { Event.find_by!(action: Event::MEMBERSHIP_ROLE_KEPT, organization: @acme) }

        assert_equal({ "role" => "owner", "wanted" => "member", "provider" => "acme" }, kept.details.slice("role", "wanted", "provider"))
        assert_match "needs an owner", kept.details["reason"]
      end

      test "a provider that changes a role ends the access tokens minted under the old one" do
        arrive([ "Everyone" ])

        membership = within { @acme.memberships.sole }
        issued = within do
          AccessToken.create!(actor: membership.actor, organization: @acme, scopes: "openid", audience: [],
                              digest: SecureRandom.uuid, expires_at: 1.hour.from_now)
        end
        keeper = create_actor(nickname: "keeper")
        within do
          membership.update!(role: "owner")
          @acme.memberships.create!(actor: keeper, role: "owner")
        end

        arrive([ "Everyone" ])

        assert_equal "member", within { membership.reload.role }
        refute within { AccessToken.live.exists?(issued.id) }
      end
    end
  end
end
