module Masks
  module Server
    require "test_helper"

    class AccessRequestsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper
      include ActiveSupport::Testing::TimeHelpers

      setup do
        host! host_for(@tenant)
        ActionMailer::Base.deliveries.clear

        @actor = create_actor(nickname: "ada", email: "ada@example.com", email_verified_at: Time.current)
        @registration = approve!(register(client_name: "Grafana", scope: "openid profile email offline_access"))
        @family = within { Group.create!(key: "family", name: "Family") }
        admitted("family")
      end

      def client
        within { Client.find_by!(client_id: @registration["client_id"]) }
      end

      def admitted(*groups)
        within { client.update!(allowed_groups: groups) }
      end

      def turned_away(actor = @actor, **params)
        sign_in_as(actor)
        authorize(client_id: @registration["client_id"], **params)
        consent! if awaiting_consent?
      end

      def rid
        Rack::Utils.parse_query(URI.parse(response.location).query)["rid"]
      end

      def ask!
        turned_away
        held = rid
        post "/authorize/refused/access", params: { rid: held }
        held
      end

      def requests
        within { AccessRequest.all.to_a }
      end

      def manage_token(actor, scope: "openid masks:manage")
        console = create_client(@tenant, allowed_scopes: "openid profile email masks:manage masks:manage:support masks:manage:security",
                                         approved_at: Time.current, grant_types: [ "authorization_code" ])

        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
        authorize(client_id: console.client_id, scope: scope, resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
              code_verifier: verifier, client_id: console.client_id)["access_token"]
      end

      def manager(scopes: "openid profile email masks:manage")
        create_actor(@tenant, nickname: "boss", scopes: scopes)
      end

      def waiting_id(bearer)
        asked = manage("query($id: ID!) { client(clientId: $id) { accessRequests { id actor { identifier } } } }",
                       bearer: bearer, id: @registration["client_id"])

        asked.dig("data", "client", "accessRequests").sole["id"]
      end

      GRANT = "mutation($id: ID!, $label: String) { grantAccess(id: $id, label: $label) { accessRequest { label grantedAt open } } }".freeze
      DECLINE = "mutation($id: ID!) { declineAccess(id: $id) { accessRequest { declinedAt open } } }".freeze

      test "somebody turned away lands on masks with a way to ask and a way back to the app" do
        turned_away

        assert_match %r{/authorize/refused\?rid=}, response.location

        follow_redirect!

        assert_response :forbidden
        assert_select "#authorize-error[data-error=access_denied]"
        assert_select "#ask-access form[action='/authorize/refused/access'] button", text: "Ask for access"
        assert_select "#back-to-app[href*='error=access_denied']"
        assert_no_match "family", response.body
        assert within { Event.where(action: Event::LOGIN_REFUSED, actor: @actor).exists? }
      end

      test "a silent request is answered with access_denied and no page" do
        turned_away(prompt: "none")

        assert_equal "access_denied", redirected["error"]
      end

      test "an app that admits everyone shows no way to ask" do
        admitted

        assert access_token_for(actor: @actor, registration: @registration)["access_token"].present?
      end

      test "asking records one request and a second visit says it is waiting" do
        held = ask!

        assert_redirected_to "/authorize/refused?rid=#{held}"

        follow_redirect!

        assert_select "#ask-access[data-waiting=true]", text: /waiting/
        assert_select "#ask-access form", count: 0
        assert_equal 1, requests.size
        assert within { Event.where(action: Event::ACCESS_REQUESTED, actor: @actor, client: client).exists? }

        post "/authorize/refused/access", params: { rid: held }

        assert_equal 1, requests.size
      end

      test "asking again within an hour after a decline is throttled" do
        held = ask!
        within { AccessRequest.sole.decline!(by: nil, journey: Journey.system) }

        post "/authorize/refused/access", params: { rid: held }

        assert_redirected_to "/authorize/refused?rid=#{held}"
        assert_equal 1, requests.size

        follow_redirect!

        assert_select "#ask-access .note-bad", text: /less than an hour ago/
      end

      test "asking with a request that is not yours or has expired is refused" do
        post "/authorize/refused/access", params: { rid: "nope" }

        assert_response :bad_request
        assert_empty requests
      end

      test "a manager sees the request on the client's page and approves it into the first allowed group" do
        ask!
        bearer = manage_token(manager)
        id = waiting_id(bearer)

        perform_enqueued_jobs { with_mailer { manage(GRANT, bearer: bearer, id: id) } }

        asked = within { AccessRequest.find(id) }

        assert_equal "family", asked.label
        assert asked.granted_at.present?
        assert within { @family.actors.exists?(@actor.id) }
        assert within { Event.where(action: Event::ACCESS_GRANTED, actor: @actor, client: client).exists? }
        assert ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@example.com" ] && mail.subject == "You can use Grafana now" }
        assert_empty manage("query($id: ID!) { client(clientId: $id) { accessRequests { id } } }",
                            bearer: bearer, id: @registration["client_id"]).dig("data", "client", "accessRequests")

        reset!
        host! host_for(@tenant)

        assert access_token_for(actor: @actor, registration: @registration)["access_token"].present?
      end

      test "a manager picks an organization role when the client allows one" do
        acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "billing" ]) }
        admitted("family", "acme:billing")
        ask!
        bearer = manage_token(manager)

        granted = manage(GRANT, bearer: bearer, id: waiting_id(bearer), label: "acme:billing")

        assert_equal "acme:billing", granted.dig("data", "grantAccess", "accessRequest", "label")
        assert_equal "billing", within { acme.memberships.accepted.find_by!(actor: @actor).role }
        assert_not within { @family.actors.exists?(@actor.id) }
      end

      test "a manager cannot grant a group the client does not allow" do
        within { Group.create!(key: "admins", name: "Admins") }
        ask!
        bearer = manage_token(manager)

        refused = manage(GRANT, bearer: bearer, id: waiting_id(bearer), label: "admins")

        assert_match(/not one of the groups/, refused["errors"].sole["message"])
        assert within { AccessRequest.sole.open? }
      end

      test "a manager declines it and the person is told" do
        ask!
        bearer = manage_token(manager)
        id = waiting_id(bearer)

        perform_enqueued_jobs { with_mailer { manage(DECLINE, bearer: bearer, id: id) } }

        assert within { AccessRequest.find(id).declined_at.present? }
        assert_not within { @family.actors.exists?(@actor.id) }
        assert within { Event.where(action: Event::ACCESS_DECLINED, actor: @actor).exists? }
        assert ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@example.com" ] && mail.subject == "Your request to use Grafana was declined" }

        again = manage(DECLINE, bearer: bearer, id: id)

        assert_match(/no access request with that id/, again["errors"].sole["message"])
      end

      test "a support manager cannot decide an access request" do
        ask!
        bearer = manage_token(manager(scopes: "openid profile email masks:manage:support"), scope: "openid masks:manage:support")

        refused = manage(GRANT, bearer: bearer, id: within { AccessRequest.sole.id })

        assert_match(/needs/, refused["errors"].sole["message"])
        assert within { AccessRequest.sole.open? }
      end

      test "an organization owner approves it from their account page" do
        acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "billing" ]) }
        owner = create_actor(nickname: "owner", email: "owner@acme.example")
        within { acme.memberships.create!(actor: owner, role: "owner") }
        admitted("acme:billing", "acme:member")
        ask!
        id = within { AccessRequest.sole.id }

        reset!
        host! host_for(@tenant)
        sign_in_as(owner)
        get "/"

        assert_select "#access-request-#{id} .item-name", text: "ada"
        assert_select "#access-role-acme-#{id} option", count: 2

        perform_enqueued_jobs { with_mailer { post "/account/organizations/acme/access/#{id}", params: { role: "billing" } } }

        assert_redirected_to "/#organization-acme"
        assert_equal "billing", within { acme.memberships.accepted.find_by!(actor: @actor).role }
        assert_equal "acme:billing", within { AccessRequest.find(id).label }
        assert ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@example.com" ] }

        follow_redirect!

        assert_select "#organization-acme .note", text: /ada is billing of Acme now and can use Grafana/
        assert_select "#access-request-#{id}", count: 0
      end

      test "an organization owner declines it from their account page" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        owner = create_actor(nickname: "owner", email: "owner@acme.example")
        within { acme.memberships.create!(actor: owner, role: "owner") }
        admitted("acme:member")
        ask!
        id = within { AccessRequest.sole.id }

        reset!
        host! host_for(@tenant)
        sign_in_as(owner)
        delete "/account/organizations/acme/access/#{id}"

        assert_redirected_to "/#organization-acme"
        assert within { AccessRequest.find(id).declined_at.present? }
        assert_not within { acme.memberships.exists?(actor: @actor) }
      end

      test "a plain member and an owner of another organization cannot decide it" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        other = within { Organization.create!(key: "other", name: "Other") }
        member = create_actor(nickname: "member", email: "member@acme.example")
        outsider = create_actor(nickname: "outsider", email: "outsider@other.example")
        within do
          acme.memberships.create!(actor: member, role: "member")
          other.memberships.create!(actor: outsider, role: "owner")
        end
        admitted("acme:member")
        ask!
        id = within { AccessRequest.sole.id }

        reset!
        host! host_for(@tenant)
        sign_in_as(member)
        get "/"

        assert_select "#access-request-#{id}", count: 0

        post "/account/organizations/acme/access/#{id}", params: { role: "member" }

        assert_redirected_to "/#organization-acme"
        assert within { AccessRequest.find(id).open? }

        reset!
        host! host_for(@tenant)
        sign_in_as(outsider)
        get "/"

        assert_select "#access-request-#{id}", count: 0

        post "/account/organizations/other/access/#{id}", params: { role: "member" }

        assert within { AccessRequest.find(id).open? }
        assert_not within { acme.memberships.exists?(actor: @actor) }
      end

      test "cleanup drops requests older than thirty days" do
        ask!
        within { AccessRequest.sole.decline!(by: nil, journey: Journey.system) }

        travel 31.days do
          CleanupJob.perform_now
        end

        assert_empty requests
      end
    end
  end
end
