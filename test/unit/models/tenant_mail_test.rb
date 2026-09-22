module Masks
  module Server
    require "test_helper"

    class TenantMailTest < ActiveSupport::TestCase
      def with_deployment(from: nil, settings: nil)
        was_from = ::Rails.configuration.masks.mail_from
        was_settings = ActionMailer::Base.smtp_settings

        ::Rails.configuration.masks.mail_from = from
        ActionMailer::Base.smtp_settings = settings || {}
        yield
      ensure
        ::Rails.configuration.masks.mail_from = was_from
        ActionMailer::Base.smtp_settings = was_settings
      end

      def smtp!(key: "relay", primary: true, **config)
        within do
          Adapters::Smtp.new(key: key, name: "Relay", primary: primary)
                        .configure({ from: "masks@example.invalid", address: "smtp.example.invalid" }.merge(config))
                        .tap(&:save!)
        end
      end

      test "a tenant with no adapter mails on whatever the deployment configured" do
        with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
          assert @tenant.mails?
          assert_equal "deploy@example.invalid", @tenant.mail_from
          assert_nil @tenant.mail_adapter
        end
      end

      test "a deployment with no mailer and a tenant with no adapter mails nowhere" do
        with_deployment do
          refute @tenant.mails?
        end
      end

      test "the primary mail adapter answers with its own settings" do
        with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
          smtp!(port: 2525, username: "postmaster", password: "hunter2",
                authentication: "login", domain: "example.invalid", tls: true)

          method, settings = within { @tenant.mail_adapter.delivery_method }

          assert @tenant.mails?
          assert_equal :smtp, method
          assert_equal "masks@example.invalid", @tenant.mail_from
          assert_equal "smtp.example.invalid", settings[:address]
          assert_equal 2525, settings[:port]
          assert_equal "postmaster", settings[:user_name]
          assert_equal "hunter2", settings[:password]
          assert_equal :login, settings[:authentication]
          assert_equal "example.invalid", settings[:domain]
          assert settings[:tls]
          refute settings[:enable_starttls]
          assert_equal OpenSSL::SSL::VERIFY_PEER, settings[:openssl_verify_mode]
        end
      end

      test "a server with no port of its own is reached on the submission port, over STARTTLS" do
        smtp!

        _, settings = within { @tenant.mail_adapter.delivery_method }

        assert_equal 587, settings[:port]
        assert_equal :plain, settings[:authentication]
        refute settings[:tls]
        assert settings[:enable_starttls]
      end

      test "secrets are encrypted at rest and never part of the settings" do
        adapter = smtp!(password: "hunter2")

        held = Adapter.connection.select_value(
          Adapter.sanitize_sql([ "SELECT secrets FROM adapters WHERE id = ?", adapter.id ])
        )

        refute_includes held.to_s, "hunter2"
        refute_includes adapter.settings.to_json, "hunter2"
        refute adapter.public_settings.key?("password")
        assert_equal [ "password" ], adapter.secrets_held
        assert_equal "hunter2", within { Adapter.find(adapter.id)[:password] }
      end

      test "a secret left blank on a later save keeps the one already held" do
        adapter = smtp!(password: "hunter2")

        within { adapter.configure(password: "", address: "other.example.invalid").save! }

        assert_equal "hunter2", within { Adapter.find(adapter.id)[:password] }
        assert_equal "other.example.invalid", within { Adapter.find(adapter.id)[:address] }
      end

      test "a port outside the range, an authentication masks cannot speak, and a bad from are refused" do
        within do
          refused = Adapters::Smtp.new(key: "bad", name: "Bad")
                                  .configure(from: "not-an-address", address: "smtp.example.invalid",
                                             port: 0, authentication: "telepathy")

          refute refused.valid?
          assert_match "Port", refused.errors.full_messages.join
          assert_match "Authentication", refused.errors.full_messages.join
          assert_match "From address", refused.errors.full_messages.join
        end
      end

      test "an archived adapter sends nothing, and another becomes primary" do
        first = smtp!
        within { first.update!(archived_at: Time.current, primary: false) }

        refute within { @tenant.mail_adapter }

        smtp!(key: "second")

        assert_equal "second", within { @tenant.mail_adapter.key }
      end

      test "a message built for a tenant carries its primary adapter's server" do
        smtp!(port: 2525, username: "postmaster", password: "hunter2")

        actor = create_actor(@tenant, nickname: "ada", email: "ada@example.invalid")

        message = within do
          held = ActorMailer.invitation(actor, "https://masks.example.invalid/a", tenant_name: @tenant.name)
          held.message
          held
        end

        assert_equal [ "masks@example.invalid" ], message.from
        assert_equal "smtp.example.invalid", message.delivery_method.settings[:address]
        assert_equal 2525, message.delivery_method.settings[:port]
      end

      test "a tenant without an adapter leaves delivery where the deployment put it" do
        with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
          actor = create_actor(@tenant, nickname: "ada", email: "ada@example.invalid")

          message = within do
            held = ActorMailer.invitation(actor, "https://masks.example.invalid/a", tenant_name: @tenant.name)
            held.message
            held
          end

          assert_equal [ "deploy@example.invalid" ], message.from
          assert_kind_of Mail::TestMailer, message.delivery_method
        end
      end

      test "one tenant's adapter is invisible to another" do
        smtp!

        assert within(other_tenant) { Adapter.count }.zero?
        assert_nil other_tenant.mail_adapter
      end
    end
  end
end
