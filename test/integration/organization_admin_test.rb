module Masks
  module Server
    require "test_helper"
    require_relative "../support/upstream"

    class OrganizationAdminTest < ActionDispatch::IntegrationTest
      include Federated

      setup do
        host! host_for(@tenant)
        @owner = create_actor(nickname: "owner", email: "owner@acme.example")
        @member = create_actor(nickname: "member", email: "member@acme.example")
        @acme = within do
          Organization.create!(key: "acme", name: "Acme", roles: [ "admin" ],
                               sign_in_policy: SignInPolicy.create!(key: "open", name: "Open", signup: true))
        end

        within do
          @acme.memberships.create!(actor: @owner, role: "owner")
          @acme.memberships.create!(actor: @member, role: "member")
        end
      end

      def member(actor, organization = @acme)
        id = within { organization.memberships.find_by!(actor: actor).id }

        "/account/organizations/#{organization.key}/members/#{id}"
      end

      def role_of(actor)
        within { @acme.memberships.find_by(actor: actor)&.role }
      end

      test "an owner sees the organization's members on their account page" do
        sign_in_as(@owner)
        get "/"

        assert_response :success
        assert_select "#organizations"
        assert_select "#organization-acme .item-name", text: /member/
      end

      test "a plain member sees their role and no member list" do
        sign_in_as(@member)
        get "/"

        assert_select "#organization-acme .entry-state", text: /member/
        assert_select "#organization-acme select[name=role]", count: 0
      end

      test "an owner adds someone by email, which invites a new account" do
        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: "new@acme.example", role: "admin" }

        assert_redirected_to "/#organizations"

        invited = within { Actor.find_by!(email: "new@acme.example") }

        refute invited.activated?
        assert_equal "admin", role_of(invited)
        assert within { Event.where(action: Event::MEMBERSHIP_ADDED, organization: @acme, by: @owner).exists? }
      end

      test "an owner changes a role and removes a member" do
        sign_in_as(@owner)

        patch member(@member), params: { role: "admin" }
        assert_equal "admin", role_of(@member)

        delete member(@member)
        assert_nil role_of(@member)
      end

      test "a member cannot change anyone, and cannot add people" do
        sign_in_as(@member)

        patch member(@owner), params: { role: "member" }
        delete member(@owner)
        post "/account/organizations/acme/members", params: { email: "sneaky@acme.example", role: "owner" }

        assert_equal "owner", role_of(@owner)
        refute within { Actor.exists?(email: "sneaky@acme.example") }
        assert_equal "Only an owner of Acme can change its members.", flash[:alert]
      end

      test "a member can leave" do
        sign_in_as(@member)
        delete member(@member)

        assert_nil role_of(@member)
      end

      test "the only owner cannot leave or demote themselves" do
        sign_in_as(@owner)

        delete member(@owner)
        assert_equal "owner", role_of(@owner)

        patch member(@owner), params: { role: "member" }
        assert_equal "owner", role_of(@owner)
      end

      test "an outsider is told they are not a member, whatever the organization" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")
        sign_in_as(outsider)

        post "/account/organizations/acme/members", params: { email: "x@acme.example", role: "member" }
        assert_equal "You are not a member of that organization.", flash[:alert]

        post "/account/organizations/initech/members", params: { email: "x@acme.example", role: "member" }
        assert_equal "You are not a member of that organization.", flash[:alert]
      end

      test "an owner cannot reach into another organization" do
        globex = within { Organization.create!(key: "globex", name: "Globex") }
        stranger = create_actor(nickname: "stranger", email: "stranger@globex.example")
        within { globex.memberships.create!(actor: stranger, role: "owner") }

        sign_in_as(@owner)
        delete member(stranger, globex)

        assert_equal "owner", within { globex.memberships.find_by!(actor: stranger).role }
      end

      test "an existing account added by an owner is only invited until it accepts" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com", email_verified_at: Time.current)

        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: "outsider@example.com", role: "member" }

        membership = within { @acme.memberships.find_by!(actor: outsider) }

        assert membership.pending?
        assert_nil within { @acme.membership_for(outsider) }

        reset!
        host! host_for(@tenant)
        sign_in_as(outsider)
        get "/"

        assert_select "#organization-acme .entry-state", text: /Waiting for you/

        post "/account/organizations/acme/accept"

        refute within { membership.reload.pending? }
        assert within { Event.where(action: Event::MEMBERSHIP_ACCEPTED, actor: outsider).exists? }
      end

      test "a person can decline an invitation to an organization" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")
        within { @acme.memberships.create!(actor: outsider, role: "member", pending: true) }

        sign_in_as(outsider)
        delete member(outsider)

        refute within { @acme.memberships.exists?(actor: outsider) }
      end

      test "an invited owner cannot change anyone before accepting" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")
        within { @acme.memberships.create!(actor: outsider, role: "owner", pending: true) }

        sign_in_as(outsider)
        delete member(@member)

        assert_equal "member", role_of(@member)
      end

      test "an owner's member list does not reveal whether an address already had an account" do
        create_actor(nickname: "existing", email: "existing@example.com")

        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: "existing@example.com", role: "member" }
        post "/account/organizations/acme/members", params: { email: "brand-new@example.com", role: "member" }
        get "/"

        names = css_select("#organization-acme .item-name").map { |held| held.text.squish }

        assert_includes names, "existing@example.com invited"
        assert_includes names, "brand-new@example.com invited"
      end

      test "an empty invitation is refused rather than matching an account with no address" do
        nameless = within { Actor.create!(nickname: "nameless", password: "password1234") }

        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: " ", role: "member" }

        assert_equal "an email address is required", flash[:alert]
        refute within { @acme.memberships.exists?(actor: nameless) }
      end

      def invite(email, role: "member")
        post "/account/organizations/acme/members", params: { email: email, role: role }
      end

      test "an unconfirmed account at the invited address cannot accept until it confirms" do
        squatter = create_actor(nickname: "squatter", email: "ceo@example.com")

        sign_in_as(@owner)
        invite("ceo@example.com")

        reset!
        host! host_for(@tenant)
        sign_in_as(squatter)
        post "/account/organizations/acme/accept"

        assert_match "Confirm ceo@example.com before joining Acme", flash[:alert]
        assert_nil within { @acme.membership_for(squatter) }

        within { squatter.verify_email!("ceo@example.com") }
        post "/account/organizations/acme/accept"

        assert_equal "member", within { @acme.membership_for(squatter)&.role }
      end

      test "an account that changed its address away from the invited one cannot accept" do
        moved = create_actor(nickname: "moved", email: "moved@example.com", email_verified_at: Time.current)

        sign_in_as(@owner)
        invite("moved@example.com")
        within { moved.update!(email: "elsewhere@example.com", email_verified_at: Time.current) }

        reset!
        host! host_for(@tenant)
        sign_in_as(moved)
        post "/account/organizations/acme/accept"

        assert_match "not the address on this account", flash[:alert]
        assert_nil within { @acme.membership_for(moved) }
      end

      test "while sign-up is closed an owner adds no one, whether or not the address has an account" do
        within { @acme.update!(sign_in_policy: nil) }
        create_actor(nickname: "existing", email: "existing@example.com")

        sign_in_as(@owner)

        invite("existing@example.com")
        existing = flash[:alert]

        invite("nobody@example.com")

        assert_equal existing.sub("existing@example.com", "nobody@example.com"), flash[:alert]
        assert_match "ask a manager", flash[:alert]
        refute within { Actor.exists?(email: "nobody@example.com") }
        assert_equal 2, within { @acme.memberships.count }
      end

      test "an owner adds anyone at a domain the organization has proven, even while sign-up is closed" do
        within { @acme.update!(sign_in_policy: nil) }
        provider = create_provider(organization: @acme, email_domains: "acme.example")
        within { DomainClaim.create!(domain: "acme.example", provider: provider).update_columns(verified_at: Time.current) }

        sign_in_as(@owner)
        invite("new@acme.example")
        invite("new@elsewhere.example")

        assert within { Actor.exists?(email: "new@acme.example") }
        refute within { Actor.exists?(email: "new@elsewhere.example") }
      end

      test "an address outside the organization's domains is refused even while sign-up is open" do
        within { @acme.sign_in_policy.update!(email_domains: [ "acme.example" ]) }

        sign_in_as(@owner)
        invite("someone@elsewhere.example")

        assert_match "ask a manager", flash[:alert]
        refute within { Actor.exists?(email: "someone@elsewhere.example") }
      end

      test "an account an owner invites gets the scopes sign-up would give it" do
        within { @acme.sign_in_policy.update!(signup_scopes: "openid email") }

        sign_in_as(@owner)
        invite("scoped@acme.example")

        assert_equal %w[email openid], within { Actor.find_by!(email: "scoped@acme.example").scope_list.sort }
      end

      test "an owner adds only so many people a day" do
        within do
          Members::DAILY_INVITATIONS.times do |index|
            Event.record!(Event::MEMBERSHIP_ADDED, actor: @member, by: @owner, organization: @acme, role: "member", n: index)
          end
        end

        sign_in_as(@owner)
        invite("one-too-many@acme.example")

        assert_match "a manager can add more", flash[:alert]
        refute within { Actor.exists?(email: "one-too-many@acme.example") }
      end

      test "an owner's page does not reveal the nickname or id of an existing account they invited" do
        hidden = create_actor(nickname: "secret-handle", email: "hidden@example.com")

        sign_in_as(@owner)
        invite("hidden@example.com")
        get "/"

        refute_includes response.body, "secret-handle"
        refute_includes response.body, hidden.uuid

        pending = within { @acme.memberships.find_by!(actor: hidden) }
        patch member(hidden), params: { role: "admin" }

        assert_equal "hidden@example.com is admin now.", flash[:notice]
        assert_equal "admin", within { pending.reload.role }
      end

      test "a member route takes a membership of this organization, never a person's id" do
        globex = within { Organization.create!(key: "globex", name: "Globex") }
        stranger = create_actor(nickname: "stranger", email: "stranger@globex.example")
        theirs = within { globex.memberships.create!(actor: stranger, role: "member") }

        sign_in_as(@owner)
        delete "/account/organizations/acme/members/#{theirs.id}"
        delete "/account/organizations/acme/members/#{@member.uuid}"

        assert within { globex.memberships.exists?(theirs.id) }
        assert_equal "member", role_of(@member)
      end
    end
  end
end
