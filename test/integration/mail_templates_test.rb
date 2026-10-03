module Masks
  module Server
    require "test_helper"

    class MailTemplatesTest < ActionDispatch::IntegrationTest
      UPDATE = <<~GRAPHQL.freeze
        mutation($kind: ID!, $subject: String, $message: String) {
          updateMailTemplate(kind: $kind, subject: $subject, message: $message) {
            mailTemplate { kind subject message placeholders }
          }
        }
      GRAPHQL

      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, scopes: "openid profile email masks:manage")
        @client = create_client(
          @tenant,
          allowed_scopes: "openid profile email masks:manage masks:manage:support",
          approved_at: Time.current,
          grant_types: [ "authorization_code", "refresh_token" ]
        )
      end

      def bearer(scope: "openid masks:manage", actor: @actor)
        sign_in_as(actor)
        authorize(client_id: @client.client_id, scope: scope, resource: issuer_for(@tenant).manage_resource)
        consent! if awaiting_consent?

        token(
          grant_type: "authorization_code", code: code_from, redirect_uri: OidcFlow::REDIRECT_URI,
          code_verifier: verifier, client_id: @client.client_id
        )["access_token"]
      end

      def ask(query, token, **variables)
        post "/manage/graphql",
             params: { query: query, variables: variables }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}" }

        JSON.parse(response.body)
      end

      def reset_mail(actor)
        with_mailer do
          within { ActorMailer.password_reset(actor, "#{origin_for(@tenant)}/reset/x", journey: Journey.system).message }
        end
      end

      test "every kind of email is listed with the placeholders it fills in" do
        body = ask("{ mailTemplates { kind subject message placeholders } }", bearer)
        listed = body.dig("data", "mailTemplates").index_by { |template| template["kind"] }

        assert_equal MailTemplate::KINDS.keys.sort, listed.keys.sort
        assert_equal %w[tenant code], listed["confirmation_code"]["placeholders"]
        assert_nil listed["password_reset"]["subject"]
      end

      test "a tenant's wording replaces the subject and the opening, and masks keeps the link and the expiry" do
        held = bearer
        body = ask(UPDATE, held, kind: "password_reset", subject: "Reset for {{name}} at {{tenant}}",
                                 message: "Hello {{nickname}},\n\nWe got your request.")
        assert_nil body["errors"]

        mail = reset_mail(@actor)

        assert_equal "Reset for #{@actor.display_name} at Demo", mail.subject
        html = mail.html_part.body.to_s
        assert_includes html, "Hello #{@actor.identifier},"
        assert_includes html, "We got your request."
        assert_includes html, "#{origin_for(@tenant)}/reset/x"
        assert_includes mail.text_part.body.to_s, "We got your request."
        assert within { Event.exists?(action: Event::MAIL_TEMPLATE_UPDATED) }
      end

      test "the wording is text, so markup in it is shown and never run" do
        ask(UPDATE, bearer, kind: "password_reset", message: %(<a href="https://evil.example">click</a>))

        html = reset_mail(@actor).html_part.body.to_s

        assert_not_includes html, %(<a href="https://evil.example">)
        assert_includes html, "&lt;a href="
      end

      test "a subject cannot break into another header" do
        ask(UPDATE, bearer, kind: "password_reset", subject: "Reset\r\nBcc: someone@example.com")

        mail = reset_mail(@actor)

        assert_equal "Reset Bcc: someone@example.com", mail.subject
        assert_nil mail.bcc
      end

      test "a placeholder the kind does not offer is refused" do
        body = ask(UPDATE, bearer, kind: "confirmation_code", message: "Hi {{name}}")

        assert_match "{{name}} is not offered here", body.dig("errors", 0, "message")
        within { assert_nil MailTemplate.for("confirmation_code") }
      end

      test "the signature closes every email" do
        ask(UPDATE, bearer, kind: "signature", message: "The {{tenant}} team")

        mail = reset_mail(@actor)

        assert_includes mail.html_part.body.to_s, "The Demo team"
        assert_includes mail.text_part.body.to_s, "The Demo team"
      end

      test "leaving both blank goes back to masks' wording" do
        held = bearer
        ask(UPDATE, held, kind: "approved", subject: "Welcome")
        ask(UPDATE, held, kind: "approved", subject: "", message: "")

        within { assert_nil MailTemplate.for("approved") }
      end

      test "a manager reset still says who started it under a tenant's wording" do
        ask(UPDATE, bearer, kind: "password_reset", message: "Your reset link is below.")
        manager = create_actor(@tenant, nickname: "ada", scopes: "openid masks:manage")

        mail = with_mailer do
          within { ActorMailer.password_reset(@actor, "#{origin_for(@tenant)}/reset/x", journey: Journey.manage(manager)).message }
        end

        assert_includes mail.text_part.body.to_s, "Your reset link is below."
        assert_includes mail.text_part.body.to_s, "ada"
      end

      test "only an owner rewords email" do
        support = create_actor(@tenant, nickname: "helper", scopes: "openid masks:manage:support")

        body = ask(UPDATE, bearer(scope: "openid masks:manage:support", actor: support), kind: "approved", subject: "Hi")

        assert_match "needs", body.dig("errors", 0, "message")
        within { assert_nil MailTemplate.for("approved") }
      end
    end
  end
end
