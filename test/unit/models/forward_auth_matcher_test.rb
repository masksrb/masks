module Masks
  module Server
    require "test_helper"

    class ForwardAuthMatcherTest < ActiveSupport::TestCase
      Person = Struct.new(:group_labels)

      def rules(*held)
        ForwardAuthRules.new(ForwardAuthRules.normalize(held))
      end

      def decide(held, path: "/", method: "GET", address: "203.0.113.9", actor: nil)
        held.decide(path: path, method: method, address: address, actor: actor).outcome
      end

      test "a path pattern covers one segment with * and any depth with **" do
        held = rules({ "paths" => [ "/admin/**" ], "outcome" => "deny" }, { "paths" => [ "/api/*/users" ], "outcome" => "token" })

        assert_equal "deny", decide(held, path: "/admin")
        assert_equal "deny", decide(held, path: "/admin/")
        assert_equal "deny", decide(held, path: "/admin/users/4")
        assert_equal "default", decide(held, path: "/administrator")
        assert_equal "token", decide(held, path: "/api/v2/users")
        assert_equal "default", decide(held, path: "/api/v2/old/users")
      end

      test "a path is read the way the app reads it, with dots resolved and escapes decoded" do
        held = rules({ "paths" => [ "/admin/**" ], "outcome" => "deny" })

        assert_equal "deny", decide(held, path: "/public/../admin/x")
        assert_equal "deny", decide(held, path: "/%61dmin")
        assert_equal "deny", decide(held, path: "//admin//x")
      end

      test "a method list covers only those methods" do
        held = rules({ "methods" => [ "get", "HEAD" ], "outcome" => "open" })

        assert_equal "open", decide(held, method: "GET")
        assert_equal "open", decide(held, method: "head")
        assert_equal "default", decide(held, method: "POST")
      end

      test "a network covers an address in its range, over IPv4 and IPv6" do
        held = rules({ "networks" => [ "192.168.0.0/16", "2001:db8::/32", "10.1.2.3" ], "outcome" => "one_factor" })

        assert_equal "one_factor", decide(held, address: "192.168.1.5")
        assert_equal "one_factor", decide(held, address: "::ffff:192.168.1.5")
        assert_equal "one_factor", decide(held, address: "2001:db8:1::9")
        assert_equal "one_factor", decide(held, address: "10.1.2.3")
        assert_equal "default", decide(held, address: "10.1.2.4")
        assert_equal "default", decide(held, address: "203.0.113.9")
        assert_equal "default", decide(held, address: nil)
        assert_equal "default", decide(held, address: "not-an-address")
      end

      test "a group rule waits for a sign-in, then covers only its members" do
        held = rules({ "groups" => [ "admins" ], "outcome" => "two_factor" }, { "outcome" => "open" })

        assert_equal "sign_in", decide(held)
        assert_equal "two_factor", decide(held, actor: Person.new(%w[admins]))
        assert_equal "open", decide(held, actor: Person.new(%w[kids]))
        assert_equal "two_factor", decide(held, actor: Person.new(%w[acme:owner admins]))
      end

      test "the first rule that covers a request wins, and no rule means today's behaviour" do
        held = rules({ "paths" => [ "/share/**" ], "outcome" => "open" },
                     { "paths" => [ "/share/private/**" ], "outcome" => "deny" })

        assert_equal "open", decide(held, path: "/share/private/x")
        assert_equal "default", decide(held, path: "/other")
        assert_equal "default", decide(rules, path: "/share/x")
        assert_nil held.decide(path: "/other", method: "GET", address: nil).rule
      end

      test "normalizing trims, upcases methods, downcases groups, and drops blanks" do
        held = ForwardAuthRules.normalize([ { "paths" => [ " /a ", "" ], "methods" => [ "post" ], "groups" => [ "Admins" ],
                                               "networks" => nil, "outcome" => " Deny " } ])

        assert_equal [ { "paths" => [ "/a" ], "methods" => [ "POST" ], "networks" => [], "groups" => [ "admins" ], "outcome" => "deny" } ],
                     held
      end

      test "every field is checked on write" do
        problems = ForwardAuthRules.problems(ForwardAuthRules.normalize([
          { "paths" => [ "admin" ], "outcome" => "open" },
          { "methods" => [ "FETCH" ], "outcome" => "open" },
          { "networks" => [ "192.168.0.0/40" ], "outcome" => "open" },
          { "groups" => [ "Not a group!" ], "outcome" => "open" },
          { "outcome" => "maybe" },
          { "outcome" => "open", "colour" => "red" },
          "open"
        ]))

        assert_equal 7, problems.size
        assert_match "rule 1 has a path of \"admin\", which does not start with /", problems[0]
        assert_match "rule 2 names a method of \"FETCH\"", problems[1]
        assert_match "rule 3 has a network of \"192.168.0.0/40\"", problems[2]
        assert_match "rule 4 names a group of \"not a group!\"", problems[3]
        assert_match "rule 5 has an outcome of \"maybe\"", problems[4]
        assert_match "rule 6 names colour, which is not a field", problems[5]
        assert_match "rule 7 is not a set of fields", problems[6]
        assert_empty ForwardAuthRules.problems(ForwardAuthRules.normalize([ { "paths" => [ "/admin/**" ], "outcome" => "deny" } ]))
        assert_equal [ "forward auth rules must be a list of rules" ], ForwardAuthRules.problems({ "outcome" => "open" })
        assert_equal [ "forward auth rules hold more than 50 rules" ], ForwardAuthRules.problems(Array.new(51) { { "outcome" => "open" } })
      end
    end
  end
end
