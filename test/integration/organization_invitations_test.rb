module Masks
  module Server
    require "test_helper"

    class OrganizationInvitationsTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper
      include ActiveSupport::Testing::TimeHelpers

      setup do
        host! host_for(@tenant)
        ActionMailer::Base.deliveries.clear

        @owner = create_actor(nickname: "owner", email: "owner@acme.example", email_verified_at: Time.current)
        @invitee = create_actor(nickname: "ada", email: "ada@acme.example", email_verified_at: Time.current)
        @acme = within do
          Organization.create!(key: "acme", name: "Acme",
                               sign_in_policy: SignInPolicy.create!(key: "open", name: "Open", signup: true))
        end

        within { @acme.memberships.create!(actor: @owner, role: "owner") }
      end

      def invite!
        sign_in_as(@owner)
        post "/account/organizations/acme/members", params: { email: "ada@acme.example", role: "member" }

        within { @acme.memberships.find_by!(actor: @invitee) }
      end

      def as(actor)
        reset!
        host! host_for(@tenant)
        sign_in_as(actor)
      end

      def resend(membership)
        post "/account/organizations/acme/members/#{membership.id}/resend"
      end

      test "an invitation records when it was sent and when it stops being accepted" do
        membership = invite!

        assert_in_delta Time.current, membership.invited_at, 5
        assert_in_delta Membership.lifetime.from_now, membership.expires_at, 5
        refute membership.expired?
      end

      test "an expired invitation cannot be accepted, and the invitee no longer sees it" do
        membership = invite!

        travel Membership.lifetime + 1.minute do
          as(@invitee)
          get "/"

          assert_select "#organization-acme", count: 0

          post "/account/organizations/acme/accept"

          assert_equal "The invitation to Acme has expired. Ask an owner to send it again.", flash[:alert]
          assert within { membership.reload.pending? }
        end
      end

      test "an owner sees an expired invitation and sends it again, which starts its lifetime over" do
        membership = invite!

        travel Membership.lifetime + 1.minute do
          as(@owner)
          get "/"

          assert_select "#organization-acme .tag-bad", text: "expired"

          perform_enqueued_jobs { with_mailer { resend(membership) } }

          assert_match "was sent again", flash[:notice]
          refute within { membership.reload.expired? }
          assert ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@acme.example" ] && mail.subject == "Join Acme" }
          assert within { Event.where(action: Event::MEMBERSHIP_RESENT, actor: @invitee, by: @owner).exists? }

          as(@invitee)
          post "/account/organizations/acme/accept"

          refute within { membership.reload.pending? }
        end
      end

      test "an invitation is sent again at most once an hour" do
        membership = invite!

        resend(membership)

        assert_equal "that invitation was sent less than an hour ago", flash[:alert]

        travel 61.minutes do
          as(@owner)
          resend(membership)

          assert_match "was sent again", flash[:notice]
        end
      end

      test "sending again counts toward an owner's invitations for the day" do
        membership = invite!

        within do
          (Members::DAILY_INVITATIONS - 1).times do
            Event.record!(Event::MEMBERSHIP_RESENT, actor: @invitee, by: @owner, organization: @acme)
          end
        end

        travel 61.minutes do
          as(@owner)
          resend(membership)

          assert_match "invitations today", flash[:alert]
        end
      end

      test "only an owner sends an invitation again" do
        membership = invite!
        member = create_actor(nickname: "member", email: "member@acme.example")
        within { @acme.memberships.create!(actor: member, role: "member") }

        travel 61.minutes do
          as(member)
          resend(membership)

          assert_equal "Only an owner of Acme can change its members.", flash[:alert]
        end
      end

      test "an invitation left expired for another lifetime is cleared away, and that is recorded" do
        stale = invite!
        fresh = within { @acme.memberships.create!(actor: create_actor(nickname: "bo", email: "bo@acme.example"), role: "member", pending: true) }

        within { stale.update_columns(invited_at: (Membership.lifetime * 2 + 1.day).ago) }
        within { fresh.update_columns(invited_at: (Membership.lifetime + 1.day).ago) }

        CleanupJob.perform_now

        refute within { Membership.exists?(stale.id) }
        assert within { Membership.exists?(fresh.id) }
        assert within { Actor.exists?(@invitee.id) }
        assert within { Event.where(action: Event::MEMBERSHIP_EXPIRED, actor: @invitee, organization: @acme).exists? }
      end

      test "a sign-in through the organization's provider still joins after the invitation expired" do
        membership = invite!

        travel Membership.lifetime + 1.minute do
          within { membership.accept!(vouched: true) }

          refute within { membership.reload.pending? }
        end
      end
    end
  end
end
