module Masks
  module Server
    require "test_helper"
    require_relative "../support/ldap_client"

    class LdapTest < ActiveSupport::TestCase
      setup do
        ::Rails.cache.clear

        @alice = create_actor(@tenant, nickname: "alice", name: "Alice Liddell", email: "alice@example.invalid",
                                       email_verified_at: Time.current, given_name: "Alice", family_name: "Liddell")
        @bob = create_actor(@tenant, nickname: "bob", email: "bob@example.invalid")
        @staff = within { Group.create!(key: "staff", name: "Staff") }
        within { @staff.add!(@alice) }

        @credential = within { LdapCredential.issue!(label: "jellyfin", by: nil) }
        @secret = @credential.secret

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

      def base(tenant = @tenant)
        "dc=#{tenant.subdomain},dc=masks"
      end

      def service(tenant = @tenant, label: "jellyfin", secret: @secret)
        client = connect
        assert_equal 0, client.bind("cn=#{label},ou=services,#{base(tenant)}", secret).code
        client
      end

      def person_dn(nickname, tenant = @tenant)
        "uid=#{nickname},ou=people,#{base(tenant)}"
      end

      def events(action)
        within { Event.where(action: action).order(:id).to_a }
      end

      test "anyone reads the root DSE, and nothing more" do
        client = connect
        result, found = client.search("", scope: 0)

        assert_equal 0, result.code
        assert_equal [ "3" ], found.first.attributes["supportedLDAPVersion"]
        assert_nil found.first.attributes["namingContexts"]

        result, found = client.search(base)
        assert_equal 50, result.code
        assert_empty found
      end

      test "a service bind names its own tenant in the root DSE" do
        _result, found = service.search("", scope: 0)

        assert_equal [ base ], found.first.attributes["namingContexts"]
      end

      test "a service finds a person with their attributes and groups" do
        result, found = service.search(base, filter: "(&(objectClass=inetOrgPerson)(uid=alice))")

        assert_equal 0, result.code
        assert_equal [ person_dn("alice") ], found.map(&:dn)

        alice = found.first.attributes
        assert_equal [ "alice" ], alice["uid"]
        assert_equal [ "Alice Liddell" ], alice["cn"]
        assert_equal [ "alice@example.invalid" ], alice["mail"]
        assert_equal [ "cn=staff,ou=groups,#{base}" ], alice["memberOf"]
        assert_equal [ @alice.uuid ], alice["entryUUID"]
        assert_includes alice["objectClass"], "inetOrgPerson"
        assert_empty alice.keys.grep(/password|secret|otp/i)
      end

      test "an unverified address is left out" do
        _result, found = service.search(person_dn("bob"), scope: 0)

        assert_equal [ "bob" ], found.first.attributes["uid"]
        assert_nil found.first.attributes["mail"]
        assert_equal [ "bob" ], found.first.attributes["cn"]
      end

      test "groups list their members, and one-level scope stays one level" do
        result, found = service.search("ou=groups,#{base}", scope: 1, filter: "(objectClass=groupOfNames)")

        assert_equal 0, result.code
        assert_equal [ "cn=staff,ou=groups,#{base}" ], found.map(&:dn)
        assert_equal [ person_dn("alice") ], found.first.attributes["member"]

        _result, found = service.search(base, scope: 1)
        assert_equal [ "ou=people,#{base}", "ou=groups,#{base}" ].sort, found.map(&:dn).sort
      end

      test "a search asks for only the attributes it wants" do
        _result, found = service.search("ou=people,#{base}", filter: "(memberOf=cn=staff,ou=groups,#{base})", attributes: %w[uid mail])

        assert_equal [ person_dn("alice") ], found.map(&:dn)
        assert_equal %w[mail uid], found.first.attributes.keys.sort
      end

      test "substring filters and size limits apply" do
        create_actor(@tenant, nickname: "alicia")

        _result, found = service.search(base, filter: "(uid=ali*)")
        assert_equal %w[alice alicia], found.map { |entry| entry.attributes["uid"].first }.sort

        result, found = service.search(base, filter: "(objectClass=person)", size_limit: 1)
        assert_equal 4, result.code
        assert_equal 1, found.size
      end

      test "suspended and unactivated people are not listed" do
        within { @bob.suspend!(reason: Actor::MANAGER) }
        within { Actor.create!(nickname: "invited", email: "invited@example.invalid") }

        _result, found = service.search(base, filter: "(objectClass=person)")

        assert_equal [ "alice" ], found.map { |entry| entry.attributes["uid"].first }
      end

      test "a missing base is reported with the nearest entry that exists" do
        result, found = service.search(person_dn("nobody"), scope: 0)

        assert_equal 32, result.code
        assert_equal "ou=people,#{base}", result.matched
        assert_empty found
      end

      test "a service sees only its own tenant" do
        create_actor(other_tenant, nickname: "mallory")
        client = service

        result, found = client.search(base(other_tenant))
        assert_equal 32, result.code
        assert_empty found

        result, found = client.search("dc=masks")
        assert_equal 32, result.code
        assert_empty found

        _result, found = client.search(base, filter: "(uid=mallory)")
        assert_empty found
      end

      test "another tenant's credential does not bind here" do
        other = Tenant.switch(other_tenant) { LdapCredential.issue!(label: "jellyfin", by: nil) }

        assert_equal 49, connect.bind("cn=jellyfin,ou=services,#{base}", other.secret).code
        assert_equal 0, connect.bind("cn=jellyfin,ou=services,#{base(other_tenant)}", other.secret).code
      end

      test "a wrong or revoked service secret is refused" do
        assert_equal 49, connect.bind("cn=jellyfin,ou=services,#{base}", "wrong").code
        assert_equal 49, connect.bind("cn=nobody,ou=services,#{base}", @secret).code

        client = service
        within { @credential.consume! }

        assert_equal 49, connect.bind("cn=jellyfin,ou=services,#{base}", @secret).code
        assert_equal 50, client.search(base).first.code
      end

      test "a person binds with their password and the bind is recorded" do
        client = connect

        assert_equal 0, client.bind(person_dn("alice"), "password").code

        bound = events(Event::LDAP_BOUND).last
        assert_equal @alice.id, bound.actor_id
        assert_equal "127.0.0.1", bound.ip_address
      end

      test "who am I names the bound DN" do
        client = connect
        who = -> { client.raw(Ldap::Ber.sequence([ Ldap::Ber.octets(Ldap::Protocol::WHO_AM_I, 0x80) ], 0x77)) }

        assert_equal "", who.call.child(3).string

        client.bind(person_dn("alice"), "password")
        response = who.call

        assert_equal 0x78, response.tag
        assert_equal 0, response.child(0).integer
        assert_equal "dn:#{person_dn('alice')}", response.child(3).string
      end

      test "a person bound connection cannot search" do
        client = connect
        client.bind(person_dn("alice"), "password")

        assert_equal 50, client.search(base).first.code
      end

      test "a wrong password is refused and recorded" do
        assert_equal 49, connect.bind(person_dn("alice"), "wrong").code

        refused = events(Event::LOGIN_REFUSED).last
        assert_equal @alice.id, refused.actor_id
        assert_equal "ldap", refused.details["via"]
        assert_equal "password", refused.details["factor"]
      end

      test "a suspended person is refused even with the right password" do
        within { @alice.suspend!(reason: Actor::MANAGER) }

        assert_equal 49, connect.bind(person_dn("alice"), "password").code
        assert_equal "suspended", events(Event::LOGIN_REFUSED).last.details["factor"]
      end

      test "a person with a second factor is refused until the tenant allows a password alone" do
        enable_otp(@alice)

        assert_equal 49, connect.bind(person_dn("alice"), "password").code
        assert_equal "second_factor", events(Event::LOGIN_REFUSED).last.details["factor"]

        @tenant.update!(ldap_password_only: true)

        assert_equal 0, connect.bind(person_dn("alice"), "password").code
      end

      test "a policy that requires a second factor refuses password binds" do
        policy = within { SignInPolicy.create!(key: "strict", name: "Strict", first_factors: %w[password], second_factors: %w[otp], second_factor_required: true) }
        @tenant.update!(sign_in_policy: policy)

        assert_equal 49, connect.bind(person_dn("bob"), "password").code
      end

      test "repeated failures for one account are throttled, even with the right password next" do
        limit = ::Rails.configuration.masks.account_attempt_limit
        limit.times { connect.bind(person_dn("alice"), "wrong") }

        result = connect.bind(person_dn("alice"), "password")

        assert_equal 53, result.code
        assert_match "too many", result.message
        assert events(Event::LOGIN_THROTTLED).any?
        assert_equal 0, connect.bind(person_dn("bob"), "password").code
      end

      test "repeated failures from one address are throttled" do
        limit = ::Rails.configuration.masks.attempt_limit
        limit.times { |index| connect.bind("cn=guess#{index},ou=services,#{base}", "wrong") }

        assert_equal 53, connect.bind("cn=jellyfin,ou=services,#{base}", @secret).code
      end

      test "an unknown tenant and a malformed name are refused alike" do
        assert_equal 49, connect.bind("uid=alice,ou=people,dc=nowhere,dc=masks", "password").code
        assert_equal 49, connect.bind("uid=alice,,", "password").code
      end

      test "an unauthenticated bind is refused and an anonymous one succeeds" do
        assert_equal 53, connect.bind(person_dn("alice"), "").code
        assert_equal 0, connect.bind("", "").code
      end

      test "writes are refused as unwilling to perform" do
        client = connect
        response = client.raw(Ldap::Ber.octets(person_dn("alice"), 0x4a))

        assert_equal 0x6b, response.tag
        assert_equal 53, response.child(0).integer

        response = client.raw(Ldap::Ber.sequence([ Ldap::Ber.octets(person_dn("alice")), Ldap::Ber.sequence([]) ], 0x66))
        assert_equal 0x67, response.tag
        assert_equal 53, response.child(0).integer
      end

      test "garbage closes the connection with a notice" do
        client = connect
        client.instance_variable_get(:@socket).write("\x30\x80\x00\x00".b)

        notice = Ldap::Ber.read(client.instance_variable_get(:@socket), limit: 10_000)
        assert_equal 0x78, notice.child(1).tag
        assert_equal 2, notice.child(1).child(0).integer
        assert client.closed?
      end

      test "with a certificate and key the listener speaks LDAPS" do
        key = OpenSSL::PKey::EC.generate("prime256v1")
        certificate = OpenSSL::X509::Certificate.new
        certificate.version = 2
        certificate.serial = 1
        certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=ldap.example.test")
        certificate.public_key = key
        certificate.not_before = 1.minute.ago
        certificate.not_after = 1.day.from_now
        certificate.sign(key, OpenSSL::Digest.new("SHA256"))

        Dir.mktmpdir do |dir|
          File.write("#{dir}/cert.pem", certificate.to_pem)
          File.write("#{dir}/key.pem", key.to_pem)

          secure = Ldap::Listener.new(host: "127.0.0.1", port: 0, logger: Logger.new(nil),
                                      tls: Ldap::Listener.tls("#{dir}/cert.pem", "#{dir}/key.pem")).start

          begin
            client = LdapClient.new(secure.port, tls: true)
            @clients << client

            assert_equal 0, client.bind(person_dn("alice"), "password").code
          ensure
            secure.stop
          end
        end
      end

      test "a certificate without a key is refused at start" do
        assert_raises(RuntimeError) { Ldap::Listener.tls("/tmp/cert.pem", nil) }
      end

      test "an unbind closes the connection" do
        client = connect
        client.unbind

        assert client.closed?
      end
    end
  end
end
