module Masks
  module Server
    require "test_helper"

    class OrganizationAdminTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @owner = create_actor(nickname: "owner", email: "owner@acme.example")
        @member = create_actor(nickname: "member", email: "member@acme.example")
        @acme = within { Organization.create!(key: "acme", name: "Acme", roles: [ "admin" ]) }

        within do
          @acme.memberships.create!(actor: @owner, role: "owner")
          @acme.memberships.create!(actor: @member, role: "member")
        end
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

        patch "/account/organizations/acme/members/#{@member.uuid}", params: { role: "admin" }
        assert_equal "admin", role_of(@member)

        delete "/account/organizations/acme/members/#{@member.uuid}"
        assert_nil role_of(@member)
      end

      test "a member cannot change anyone, and cannot add people" do
        sign_in_as(@member)

        patch "/account/organizations/acme/members/#{@owner.uuid}", params: { role: "member" }
        delete "/account/organizations/acme/members/#{@owner.uuid}"
        post "/account/organizations/acme/members", params: { email: "sneaky@acme.example", role: "owner" }

        assert_equal "owner", role_of(@owner)
        refute within { Actor.exists?(email: "sneaky@acme.example") }
        assert_equal "Only an owner of Acme can change its members.", flash[:alert]
      end

      test "a member can leave" do
        sign_in_as(@member)
        delete "/account/organizations/acme/members/#{@member.uuid}"

        assert_nil role_of(@member)
      end

      test "the only owner cannot leave or demote themselves" do
        sign_in_as(@owner)

        delete "/account/organizations/acme/members/#{@owner.uuid}"
        assert_equal "owner", role_of(@owner)

        patch "/account/organizations/acme/members/#{@owner.uuid}", params: { role: "member" }
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
        delete "/account/organizations/globex/members/#{stranger.uuid}"

        assert_equal "owner", within { globex.memberships.find_by!(actor: stranger).role }
      end

      test "an existing account added by an owner is only invited until it accepts" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")

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
        delete "/account/organizations/acme/members/#{outsider.uuid}"

        refute within { @acme.memberships.exists?(actor: outsider) }
      end

      test "an invited owner cannot change anyone before accepting" do
        outsider = create_actor(nickname: "outsider", email: "outsider@example.com")
        within { @acme.memberships.create!(actor: outsider, role: "owner", pending: true) }

        sign_in_as(outsider)
        delete "/account/organizations/acme/members/#{@member.uuid}"

        assert_equal "member", role_of(@member)
      end

      test "an owner's member list does not reveal whether an address already had an account" do
        create_actor(nickname: "existing", email: "existing@example.com")

        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: "existing@example.com", role: "member" }
        post "/account/organizations/acme/members", params: { email: "brand-new@example.com", role: "member" }
        get "/"

        assert_select "#organization-acme .item-name", text: /existing@example.com.*invited/m
        assert_select "#organization-acme .item-name", text: /brand-new@example.com.*invited/m
      end
    end
  end
end
