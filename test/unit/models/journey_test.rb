module Masks
  module Server
    require "test_helper"

    class JourneyTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup { ActionMailer::Base.deliveries.clear }

      def code_mail(client)
        within do
          journey = Journey.new(kind: Journey::SIGN_IN, via: Journey::AUTHORIZATION, client: client)
          ActorMailer.confirmation_code("sam@example.com", "482913", journey: journey).message
        end
      end

      test "an email sent while signing in to an approved app is headed by that app" do
        client = create_client(@tenant, name: "Acme Notes", approved_at: Time.current)

        with_mailer do
          mail = code_mail(client)

          assert_includes mail.html_part.decoded, "Acme Notes"
          assert_includes mail.html_part.decoded, ">A<"
          assert_includes mail.subject, "Acme Notes"
          assert_includes mail.html_part.decoded, "Demo"
        end
      end

      test "an app nobody approved never heads an email" do
        client = create_client(@tenant, name: "Your Bank")

        with_mailer do
          mail = code_mail(client)

          assert_not_includes mail.html_part.decoded, "Your Bank"
          assert_includes mail.subject, "Demo"
        end
      end

      test "a journey whose app was deleted before the mail went out still sends, headed by the tenant" do
        client = create_client(@tenant, name: "Acme Notes", approved_at: Time.current)

        with_mailer do
          within do
            journey = Journey.new(kind: Journey::SIGN_IN, client: client, origin: "https://acme.auth.example")
            ActorMailer.confirmation_code("sam@example.com", "482913", journey: journey).deliver_later
            client.destroy!
          end

          within { perform_enqueued_jobs }

          assert_not_includes ActionMailer::Base.deliveries.sole.html_part.decoded, "Acme Notes"
        end
      end

            test "a journey survives the queue with its app" do
        client = create_client(@tenant, name: "Acme Notes", approved_at: Time.current)

        with_mailer do
          within do
            journey = Journey.new(kind: Journey::SIGN_IN, via: Journey::DEVICE, client: client,
                                  origin: "https://acme.auth.example")
            ActorMailer.confirmation_code("sam@example.com", "482913", journey: journey).deliver_later
          end

          within { perform_enqueued_jobs }

          assert_includes ActionMailer::Base.deliveries.sole.html_part.decoded, "Acme Notes"
        end
      end
    end
  end
end
