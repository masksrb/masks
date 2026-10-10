module Masks
  module Server
    require "test_helper"

    class AddressesTest < ActionDispatch::IntegrationTest
      include ActiveJob::TestHelper

      setup do
        host! host_for(@tenant)

        within(@tenant) { Adapters::SmsLog.create!(key: "log", name: "Log", primary: true) }

        @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com")
        within(@tenant) { @actor.update!(email_verified_at: Time.current) }

        ActionMailer::Base.deliveries.clear
        Adapters::SmsLog.deliveries.clear
      end

      def reloaded
        within(@tenant) { @actor.reload }
      end

      def mailed_code
        ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
      end

      def texted_code
        Adapters::SmsLog.deliveries.last[:body][/\b\d{6}\b/]
      end

      def bearer(actor)
        client = create_client(
          @tenant,
          allowed_scopes: "openid profile email masks:manage",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )

        sign_in_as(actor)
        authorize(client_id: client.client_id, scope: "openid masks:manage", resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(
          grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
          code_verifier: verifier, client_id: client.client_id
        )["access_token"]
      end

      def ask(query, token, **variables)
        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }

        JSON.parse(response.body)
      end

      test "a person changes their email address once the new one proves it gets mail" do
        with_mailer do
          sign_in_as(@actor)

          perform_enqueued_jobs { post "/account/addresses/email", params: { address: "ada@new.example" } }

          assert_redirected_to "/#email"
          assert_equal [ "ada@new.example" ], ActionMailer::Base.deliveries.last.to
          assert_equal "ada@example.com", reloaded.email

          code = mailed_code
          perform_enqueued_jobs { patch "/account/addresses/email", params: { code: code } }

          assert_equal "ada@new.example", reloaded.email
          assert reloaded.email_verified_at.present?
          assert_equal [ "ada@example.com" ], ActionMailer::Base.deliveries.last.to
          assert within(@tenant) { Event.where(action: Event::EMAIL_CHANGED, actor: @actor).exists? }
        end
      end

      test "a wrong code changes nothing" do
        with_mailer do
          sign_in_as(@actor)

          perform_enqueued_jobs { post "/account/addresses/email", params: { address: "ada@new.example" } }
          patch "/account/addresses/email", params: { code: "000000" }

          assert_equal flash[:alert], I18n.t("addresses.invalid_code")
          assert_equal "ada@example.com", reloaded.email
        end
      end

      test "an address another account uses is refused only after its code is entered" do
        create_actor(@tenant, nickname: "grace", email: "grace@example.com")

        with_mailer do
          sign_in_as(@actor)

          perform_enqueued_jobs { post "/account/addresses/email", params: { address: "grace@example.com" } }

          assert_equal flash[:notice], I18n.t("addresses.email.sent", to: "grace@example.com")

          patch "/account/addresses/email", params: { code: mailed_code }

          assert_equal flash[:alert], I18n.t("addresses.email.taken")
          assert_equal "ada@example.com", reloaded.email
        end
      end

      test "an unconfirmed previous address is not told about the change" do
        within(@tenant) { @actor.update!(email_verified_at: nil) }

        with_mailer do
          sign_in_as(@actor)

          perform_enqueued_jobs { post "/account/addresses/email", params: { address: "ada@new.example" } }
          code = mailed_code
          ActionMailer::Base.deliveries.clear

          perform_enqueued_jobs { patch "/account/addresses/email", params: { code: code } }

          assert_equal "ada@new.example", reloaded.email
          assert_empty ActionMailer::Base.deliveries.select { |mail| mail.to == [ "ada@example.com" ] }
        end
      end

      test "a person adds a phone number by entering the code texted to it, and removes it" do
        sign_in_as(@actor)

        perform_enqueued_jobs { post "/account/addresses/phone", params: { address: "+1 555 123 4567" } }

        assert_redirected_to "/#phone"
        assert_equal "+15551234567", Adapters::SmsLog.deliveries.last[:to]

        patch "/account/addresses/phone", params: { code: texted_code }

        assert_equal "+15551234567", reloaded.phone
        assert reloaded.phone_verified_at.present?

        delete "/account/addresses/phone"

        assert_nil reloaded.phone
        assert within(@tenant) { Event.where(action: Event::PHONE_REMOVED, actor: @actor).exists? }
      end

      test "changing an address asks for a recent sign-in" do
        with_mailer do
          sign_in_as(@actor)

          travel 16.minutes do
            post "/account/addresses/email", params: { address: "ada@new.example" }

            assert_redirected_to %r{/login}
            assert_empty ActionMailer::Base.deliveries
          end
        end
      end

      test "an account a directory manages cannot change its own addresses" do
        within(@tenant) { @actor.update!(external_id: "dir-1") }

        with_mailer do
          sign_in_as(@actor)

          post "/account/addresses/email", params: { address: "ada@new.example" }

          assert_equal flash[:alert], I18n.t("addresses.directed")
          assert_empty ActionMailer::Base.deliveries
        end
      end

      test "a manager changing someone's email tells the previous address" do
        with_mailer do
          admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")
          token = bearer(admin)

          perform_enqueued_jobs do
            ask(<<~GQL, token, uuid: @actor.uuid)
              mutation Update($uuid: ID!) { updateActor(uuid: $uuid, email: "ada@elsewhere.example") { actor { email } } }
            GQL
          end

          assert ActionMailer::Base.deliveries.any? { |mail| mail.to == [ "ada@example.com" ] }
        end
      end
    end
  end
end
