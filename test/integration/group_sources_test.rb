module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"

    class GroupSourcesTest < ActionDispatch::IntegrationTest
      include Federated

      setup do
        @owner = create_actor(@tenant, nickname: "boss", scopes: "openid profile email masks:manage")
        @ada = create_actor(nickname: "ada", email: "ada@example.com", email_verified_at: Time.current)
        @registration = approve!(register(scope: "openid profile email offline_access groups"))
      end

      def bearer
        @bearer ||= begin
          console = create_client(@tenant, allowed_scopes: "openid profile email masks:manage", approved_at: Time.current,
                                           grant_types: [ "authorization_code" ])

          token = manage_bearer(@owner, console)
          reset!
          host! host_for(@tenant)
          token
        end
      end

      def ask(query, **variables)
        manage(query, bearer: bearer, **variables)
      end

      def held(key)
        within { Group.find_by!(key: key).members.includes(:actor).to_h { |member| [ member.actor.nickname, member.sourced_by ] } }
      end

      def groups_claim(actor)
        reset!
        host! host_for(@tenant)
        code = authorized_code(actor: actor, registration: @registration, scope: "openid groups")
        granted = token(grant_type: "authorization_code", code: code, redirect_uri: OidcFlow::REDIRECT_URI, code_verifier: verifier,
                        client_id: @registration["client_id"], client_secret: @registration["client_secret"])

        claims_in(granted["id_token"])["groups"]
      end

      CREATE = <<~GQL.freeze
        mutation Create($key: String!, $name: String!, $source: String, $rule: [GroupConditionInput!], $parentLabels: [String!],
                        $providerKey: String, $upstreamGroup: String) {
          createGroup(key: $key, name: $name, source: $source, rule: $rule, parentLabels: $parentLabels,
                      providerKey: $providerKey, upstreamGroup: $upstreamGroup) {
            group { key source memberCount rule { kind field value } parentLabels providerKey upstreamGroup memberships { actor { nickname } sourcedBy } }
          }
        }
      GQL

      test "a rule group fills itself, follows a profile change, and puts its members in the groups claim" do
        made = ask(CREATE, key: "staff", name: "Staff", source: "rule", rule: [ { kind: "email_domain", value: "example.com" } ])

        assert_nil made["errors"]
        group = made.dig("data", "createGroup", "group")
        assert_equal "rule", group["source"]
        assert_equal [ { "kind" => "email_domain", "field" => nil, "value" => "example.com" } ], group["rule"]
        assert_equal({ "ada" => "rule" }, held("staff"))

        assert_includes groups_claim(@ada), "staff"

        within { @ada.update!(email: "ada@example.org", email_verified_at: Time.current) }

        assert_empty held("staff")
      end

      test "a rule a manager writes badly is refused with what is wrong" do
        answer = ask(CREATE, key: "staff", name: "Staff", source: "rule", rule: [ { kind: "profile", field: "password_digest", value: "x" } ])

        assert_match "not a profile field", answer["errors"].to_s
        refute within { Group.exists?(key: "staff") }
      end

      test "a nested group holds everyone in its parents and an organization role, and the claim shows it" do
        within do
          Group.create!(key: "family", name: "Family").add!(@ada)
          acme = Organization.create!(key: "acme", name: "Acme")
          acme.memberships.create!(actor: @owner, role: "owner")
        end

        made = ask(CREATE, key: "everyone", name: "Everyone", source: "group", parentLabels: [ "family", "acme:owner" ])

        assert_nil made["errors"]
        assert_equal({ "ada" => "group", "boss" => "group" }, held("everyone"))
        assert_equal %w[everyone family], groups_claim(@ada)

        within { Group.find_by!(key: "family").remove!(@ada) }

        assert_equal({ "boss" => "group" }, held("everyone"))
      end

      test "a group cannot be made a parent of its own parent through the manage API" do
        ask(CREATE, key: "staff", name: "Staff")
        ask(CREATE, key: "admins", name: "Admins", source: "group", parentLabels: [ "staff" ])

        answer = ask('mutation { updateGroup(key: "staff", source: "group", parentLabels: ["admins"]) { group { key } } }')

        assert_match "inside itself", answer["errors"].to_s
        assert_equal "manual", within { Group.find_by!(key: "staff").source }
      end

      test "a sourced member is not removed by hand, and a manager's own addition stays when the source drops them" do
        ask(CREATE, key: "staff", name: "Staff", source: "rule", rule: [ { kind: "email_domain", value: "example.com" } ])

        refused = ask('mutation Remove($uuid: ID!) { removeGroupMember(key: "staff", uuid: $uuid) { group { key } } }', uuid: @ada.uuid)

        assert_match "the rule decides", refused["errors"].to_s
        assert_equal({ "ada" => "rule" }, held("staff"))

        ask('mutation Add($uuid: ID!) { addGroupMember(key: "staff", uuid: $uuid) { group { key } } }', uuid: @ada.uuid)

        assert_equal({ "ada" => nil }, held("staff"))

        within { @ada.update!(email: "ada@example.org", email_verified_at: Time.current) }

        assert_equal({ "ada" => nil }, held("staff"))
      end

      def arrive(groups)
        reset!
        host! host_for(@tenant)
        authorize(client_id: @registration["client_id"], scope: "openid profile email offline_access")
        finish_sso(sub: "upstream-7", email: "grace@upstream.test", groups: groups, handoff: begin_sso(rid: current_rid))
      end

      test "a provider group fills at sign-in and empties when a later sign-in leaves the upstream group out" do
        within { DomainClaim.create!(domain: "upstream.test", verified_at: Time.current) }
        create_provider(role: "delegate", email_domains: "upstream.test")
        made = ask(CREATE, key: "engineers", name: "Engineers", source: "provider", providerKey: "acme", upstreamGroup: "Engineering")

        assert_nil made["errors"]
        assert_equal "acme", made.dig("data", "createGroup", "group", "providerKey")

        arrive([ "Engineering", "Everyone" ])
        grace = within { Actor.find_by!(email: "grace@upstream.test") }

        assert_equal({ grace.nickname => "provider" }, held("engineers"))

        arrive([ "Everyone" ])

        assert_empty held("engineers")
      end

      test "an actor's page says what put them in each group" do
        ask(CREATE, key: "staff", name: "Staff", source: "rule", rule: [ { kind: "email_domain", value: "example.com" } ])

        answer = ask("query Held($uuid: ID!) { actor(uuid: $uuid) { groupMemberships { group { key } sourcedBy } groupLabels } }", uuid: @ada.uuid)

        assert_equal [ { "group" => { "key" => "staff" }, "sourcedBy" => "rule" } ], answer.dig("data", "actor", "groupMemberships")
        assert_equal %w[staff], answer.dig("data", "actor", "groupLabels")
      end

      test "a refresh fills the group now and records the change once" do
        ask(CREATE, key: "staff", name: "Staff", source: "rule", rule: [ { kind: "email_domain", value: "example.com" } ])
        within do
          Group.find_by!(key: "staff").members.delete_all
          Event.where(action: Event::GROUP_REFRESHED).delete_all
        end

        answer = ask('mutation { refreshGroup(key: "staff") { group { memberCount } } }')

        assert_equal 1, answer.dig("data", "refreshGroup", "group", "memberCount")
        refreshed = within { Event.where(action: Event::GROUP_REFRESHED).sole }
        assert_equal @owner.id, refreshed.by_id

        ask('mutation { refreshGroup(key: "staff") { group { memberCount } } }')

        assert_equal 1, within { Event.where(action: Event::GROUP_REFRESHED).count }
      end
    end
  end
end
