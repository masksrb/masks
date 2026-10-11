module Masks
  module Server
    require "test_helper"

    class LdapDnTest < ActiveSupport::TestCase
      Dn = Ldap::Dn

      test "a DN parses into its parts and prints back" do
        dn = Dn.parse("uid=alice, ou=People ,dc=demo,dc=masks")

        assert_equal 4, dn.depth
        assert_equal "uid", dn.first_type
        assert_equal "alice", dn.first_value
        assert_equal "uid=alice,ou=People,dc=demo,dc=masks", dn.to_s
      end

      test "comparison ignores case and spacing" do
        assert_equal Dn.parse("UID=Alice,OU=people,DC=demo,DC=masks"), Dn.parse("uid=alice, ou=people, dc=demo, dc=masks")
      end

      test "ancestry follows the suffix" do
        person = Dn.parse("uid=alice,ou=people,dc=demo,dc=masks")

        assert person.under?(Dn.parse("dc=demo,dc=masks"))
        assert person.under?(person)
        assert person.under?(Dn.parse(""))
        assert_not person.under?(Dn.parse("dc=other,dc=masks"))
        assert_equal Dn.parse("ou=people,dc=demo,dc=masks"), person.parent
      end

      test "escaped characters survive a round trip" do
        dn = Dn.build([ :cn, "Smith, John+ <x>" ], [ :dc, "masks" ])

        assert_equal "cn=Smith\\, John\\+ \\<x\\>,dc=masks", dn.to_s
        assert_equal "Smith, John+ <x>", Dn.parse(dn.to_s).first_value
        assert_equal "a,b", Dn.parse("cn=a\\2cb").first_value
      end

      test "leading and trailing spaces are escaped" do
        assert_equal "\\ x\\ ", Dn.escape(" x ")
        assert_equal " x ", Dn.parse("cn=\\ x\\ ").first_value
      end

      test "malformed DNs are refused" do
        [ "uid", "uid=a,,dc=masks", "=a", "cn=#0403", "cn=a\\", "1uid=a" ].each do |text|
          assert_raises(Dn::Invalid, text) { Dn.parse(text) }
        end
      end

      test "an overlong DN is refused" do
        assert_raises(Dn::Invalid) { Dn.parse("cn=#{'a' * 2000}") }
      end
    end
  end
end
