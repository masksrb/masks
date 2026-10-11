module Masks
  module Server
    require "test_helper"

    class LdapFilterTest < ActiveSupport::TestCase
      Ber = Ldap::Ber
      Filter = Ldap::Filter

      setup do
        @entry = Ldap::Entry.new(
          Ldap::Dn.parse("uid=alice,ou=people,dc=demo,dc=masks"),
          "objectClass" => %w[top person inetOrgPerson],
          "uid" => "alice",
          "cn" => "Alice Liddell",
          "mail" => nil,
          "memberOf" => [ "cn=staff,ou=groups,dc=demo,dc=masks" ]
        )
      end

      def matches?(text)
        Filter.parse(text).match(@entry)
      end

      test "equality ignores case" do
        assert matches?("(uid=ALICE)")
        assert matches?("(objectclass=inetorgperson)")
        assert_not matches?("(uid=bob)")
      end

      test "presence needs a value" do
        assert matches?("(objectClass=*)")
        assert_not matches?("(mail=*)")
      end

      test "and, or, and not combine" do
        assert matches?("(&(objectClass=person)(uid=alice))")
        assert_not matches?("(&(objectClass=person)(uid=bob))")
        assert matches?("(|(uid=bob)(uid=alice))")
        assert matches?("(!(uid=bob))")
        assert matches?("(&(objectClass=person)(!(mail=*)))")
      end

      test "substrings match the start, middle, and end" do
        assert matches?("(cn=Ali*)")
        assert matches?("(cn=*Lidd*)")
        assert matches?("(cn=*dell)")
        assert matches?("(cn=A*ce*ll)")
        assert_not matches?("(cn=*Bob*)")
        assert_not matches?("(cn=Alice*Alice)")
      end

      test "DN values compare by their normal form" do
        assert matches?("(memberOf=CN=Staff, OU=Groups, DC=demo, DC=masks)")
        assert_not matches?("(memberOf=cn=other,ou=groups,dc=demo,dc=masks)")
      end

      test "an extensible match is undefined, and not of undefined stays undefined" do
        filter = Filter.from(Ber.decode(Ber.sequence([ Ber.octets("x", 0x82) ], Filter::EXTENSIBLE)))

        assert_nil filter.match(@entry)
        assert_nil Filter::Negated.new(filter: filter).match(@entry)
        assert_equal false, Filter::All.new(filters: [ filter, Filter.parse("(uid=bob)") ]).match(@entry)
        assert_equal true, Filter::Any.new(filters: [ filter, Filter.parse("(uid=alice)") ]).match(@entry)
      end

      test "filters decode from BER" do
        encoded = Ber.sequence(
          [
            Ber.sequence([ Ber.octets("objectClass"), Ber.octets("person") ], Filter::EQUALITY),
            Ber.octets("uid", Filter::PRESENT),
            Ber.sequence([ Ber.octets("cn"), Ber.sequence([ Ber.octets("Ali", Filter::INITIAL), Ber.octets("dell", Filter::FINAL) ]) ],
                         Filter::SUBSTRINGS),
            Ber.sequence([ Ber.sequence([ Ber.octets("uid"), Ber.octets("bob") ], Filter::EQUALITY) ], Filter::NOT)
          ],
          Filter::AND
        )

        assert Filter.from(Ber.decode(encoded)).match(@entry)
      end

      test "an unknown filter choice is refused" do
        assert_raises(Filter::Invalid) { Filter.from(Ber.decode(Ber.octets("x", 0x8f))) }
      end

      test "a uid the filter requires is pinned" do
        assert_equal "alice", Filter.pinned(Filter.parse("(&(objectClass=person)(uid=alice))"), "uid")
        assert_nil Filter.pinned(Filter.parse("(|(uid=alice)(uid=bob))"), "uid")
      end

      test "escaped filter values decode" do
        assert Filter.parse("(cn=Alice\\20Liddell)").match(@entry)
      end
    end
  end
end
