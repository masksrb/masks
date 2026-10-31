module Masks
  module Server
    require "test_helper"
    require_relative "../support/ldap_client"

    class AppPasswordsLdapTest < ActiveSupport::TestCase
      setup do
        ::Rails.cache.clear
        @tenant.update!(ldap_enabled: true)

        @alice = create_actor(@tenant, nickname: "alice", email: "alice@example.invalid", otp: true)
        @nas = create_client(@tenant, name: "NAS", approved_at: Time.current, app_passwords: true)
        @media = create_client(@tenant, name: "Media", approved_at: Time.current, app_passwords: true)

        @for_nas = within { LdapCredential.issue!(label: "nas", by: nil, client: @nas) }
        @for_media = within { LdapCredential.issue!(label: "media", by: nil, client: @media) }
        @plain = within { LdapCredential.issue!(label: "plain", by: nil) }

        @password = within { AppPassword.issue!(actor: @alice, client: @nas, name: "The NAS") }
        @secret = @password.secret

        @listener = Ldap::Listener.new(host: "127.0.0.1", port: 0, logger: Logger.new(nil)).start
        @clients = []
      end

      teardown do
        @clients.each(&:close)
        @listener.stop
      end

      def connect
        LdapClient.new(@listener.port).tap { |client| @clients << client }
      end

      def base
        "dc=#{@tenant.subdomain},dc=masks"
      end

      def service(credential)
        client = connect
        assert_equal 0, client.bind("cn=#{credential.label},ou=services,#{base}", credential.secret).code
        client
      end

      def alice
        "uid=alice,ou=people,#{base}"
      end

      def events(action)
        within { Event.where(action: action).order(:id).to_a }
      end

      test "an app password binds through the credential issued for its app, second factor and all" do
        assert_equal 49, connect.bind(alice, "password").code
        assert_equal "second_factor", events(Event::LOGIN_REFUSED).last.details["factor"]

        client = service(@for_nas)

        assert_equal 0, client.bind(alice, @secret).code

        bound = events(Event::LDAP_BOUND).sole
        assert_equal @alice.id, bound.actor_id
        assert_equal "app_password", bound.details["factor"]
        assert_predicate within { @password.reload.used_at }, :present?
        assert_equal @nas.id, events(Event::APP_PASSWORD_USED).sole.client_id

        assert_equal 0, service(@for_nas).bind(alice, @secret.upcase.delete("-")).code
      end

      test "an app password is refused through another app's credential, a plain credential, and a direct bind" do
        assert_equal 49, service(@for_media).bind(alice, @secret).code
        assert_equal "app_password", events(Event::LOGIN_REFUSED).last.details["factor"]
        assert_equal "ldap", events(Event::LOGIN_REFUSED).last.details["via"]

        assert_equal 49, service(@plain).bind(alice, @secret).code
        assert_equal "password", events(Event::LOGIN_REFUSED).last.details["factor"]

        assert_equal 49, connect.bind(alice, @secret).code
        assert_empty events(Event::LDAP_BOUND)
      end

      test "a revoked app password and a client that stopped accepting them are refused" do
        within { @password.revoke! }
        assert_equal 49, service(@for_nas).bind(alice, @secret).code

        fresh = within { AppPassword.issue!(actor: @alice, client: @nas, name: "Again") }
        assert_equal 0, service(@for_nas).bind(alice, fresh.secret).code

        within { @nas.update!(app_passwords: false) }
        assert_equal 49, service(@for_nas).bind(alice, fresh.secret).code
        assert_equal "factor-not-offered", events(Event::LOGIN_REFUSED).last.details["factor"]
      end

      test "wrong app passwords count toward the account's limit, and the right one is throttled after" do
        limit = Throttle.limit(:account_attempt)
        wrong = AppPassword.grouped("b" * AppPassword::LENGTH)

        limit.times { assert_equal 49, service(@for_nas).bind(alice, wrong).code }

        result = service(@for_nas).bind(alice, @secret)

        assert_equal 53, result.code
        assert_match "too many", result.message
        assert events(Event::LIMIT_REACHED).any?
      end

      test "a credential's app is listed and chosen in the manage API" do
        assert_equal @nas.id, within { @for_nas.reload.client_id }
        assert_nil within { @plain.reload.client_id }
      end
    end
  end
end
