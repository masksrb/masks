module Masks
  module Server
    require "test_helper"

    class OrganizationEmailTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)
        ActionMailer::Base.deliveries.clear

        @owner = create_actor(nickname: "owner", email: "owner@acme.example", email_verified_at: Time.current)
        @member = create_actor(nickname: "member", email: "member@acme.example", email_verified_at: Time.current)
        @acme = within do
          Organization.create!(key: "acme", name: "Acme", roles: [ "admin" ],
                               sign_in_policy: SignInPolicy.create!(key: "open", name: "Open", signup: true))
        end

        within do
          @acme.memberships.create!(actor: @owner, role: "owner")
          @acme.memberships.create!(actor: @member, role: "member")
        end
      end

      def delivered(&)
        with_mailer { perform_enqueued_jobs(&) }

        ActionMailer::Base.deliveries
      end

      def member(actor)
        "/account/organizations/acme/members/#{within { @acme.memberships.find_by!(actor: actor).id }}"
      end

      test "a person who already has an account is told they were added, and where to accept" do
        create_actor(nickname: "ada", email: "ada@acme.example", email_verified_at: Time.current)

        mails = delivered do
          sign_in_as(@owner)
          post "/account/organizations/acme/members", params: { email: "ada@acme.example", role: "admin" }
        end

        mail = mails.find { |sent| sent.to == [ "ada@acme.example" ] }

        assert mail, "no email reached the person who was added"
        assert_equal "Join Acme", mail.subject

        body = mail.text_part.body.to_s

        assert_includes body, "owner invited you to join Acme as admin."
        assert_includes body, "Nothing changes until you accept."
        assert_includes body, "#organization-acme"
        refute_includes body, "password"
      end

      test "a new address is invited to the organization, not only to the tenant" do
        mails = delivered do
          sign_in_as(@owner)
          post "/account/organizations/acme/members", params: { email: "new@acme.example", role: "admin" }
        end

        mail = mails.find { |sent| sent.to == [ "new@acme.example" ] }

        assert_equal "Join Acme", mail.subject

        body = mail.text_part.body.to_s

        assert_includes body, "owner invited you to join Acme as admin."
        assert_includes body, "Acme is waiting on your account page"
        assert_match %r{/invite/}, body
      end

      test "an account whose address is unconfirmed is not written to" do
        create_actor(nickname: "unsure", email: "unsure@acme.example")

        mails = delivered do
          sign_in_as(@owner)
          post "/account/organizations/acme/members", params: { email: "unsure@acme.example", role: "member" }
        end

        assert_empty mails.select { |sent| sent.to == [ "unsure@acme.example" ] }
      end

      test "a changed role reaches the member by email, with who to ask" do
        mails = delivered do
          sign_in_as(@owner)
          patch member(@member), params: { role: "admin" }
        end

        mail = mails.find { |sent| sent.to == [ "member@acme.example" ] }

        assert mail, "no email told the member their role changed"

        body = mail.text_part.body.to_s

        assert_includes body, "Your role in Acme changed from member to admin."
        assert_includes body, "owner did this, not you."
        assert_includes body, "ask an owner of Acme"
        refute_includes body, "change your password"
      end

      test "being removed is emailed, and leaving is not" do
        other = create_actor(nickname: "other", email: "other@acme.example", email_verified_at: Time.current)
        within { @acme.memberships.create!(actor: other, role: "member") }

        mails = delivered do
          sign_in_as(@owner)
          delete member(@member)

          reset!
          host! host_for(@tenant)
          sign_in_as(other)
          delete member(other)
        end

        assert mails.find { |sent| sent.to == [ "member@acme.example" ] && sent.text_part.body.to_s.include?("You were removed from Acme.") }
        assert_empty mails.select { |sent| sent.to == [ "other@acme.example" ] && sent.subject.include?("Removed") }
      end
    end
  end
end
