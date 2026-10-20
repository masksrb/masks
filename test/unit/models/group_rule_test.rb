module Masks
  module Server
    require "test_helper"

    class GroupRuleTest < ActiveSupport::TestCase
      def domain(value)
        { "kind" => "email_domain", "value" => value }
      end

      def profile(field, value)
        { "kind" => "profile", "field" => field, "value" => value }
      end

      def matching(rule)
        within { GroupRule.scope(rule).pluck(:nickname).sort }
      end

      setup do
        within do
          Actor.create!(nickname: "ada", email: "ada@example.com", email_verified_at: Time.current, locale: "en", external_id: "1")
          Actor.create!(nickname: "grace", email: "grace@example.com", locale: "en", external_id: "2")
          Actor.create!(nickname: "linus", email: "linus@example.org", email_verified_at: Time.current, locale: "fi", external_id: "3")
        end
      end

      test "a profile condition skips someone who sets their own profile, so nobody joins by editing it" do
        within { Actor.create!(nickname: "eve", email: "eve@example.net", email_verified_at: Time.current, locale: "en") }

        assert_equal %w[ada grace], matching([ profile("locale", "en") ])
      end

      test "an email domain condition reads only a verified address" do
        assert_equal %w[ada], matching([ domain("example.com") ])
      end

      test "a profile condition reads one field, and every condition must hold" do
        assert_equal %w[ada grace], matching([ profile("locale", "en") ])
        assert_equal %w[ada], matching([ profile("locale", "en"), domain("example.com") ])
        assert_empty matching([ profile("locale", "fi"), domain("example.com") ])
      end

      test "a condition is normalized before it is checked" do
        normalized = GroupRule.normalize([ { kind: " email_domain ", value: " @Example.COM " }, { "kind" => "profile", "field" => "locale", "value" => " en " } ])

        assert_equal [ domain("example.com"), profile("locale", "en") ], normalized
      end

      test "a rule refuses an unknown kind, an unknown field, a bad domain, and too many conditions" do
        assert_match "kind of condition", GroupRule.problems([ { "kind" => "sql", "value" => "1=1" } ]).join
        assert_match "not a profile field", GroupRule.problems([ profile("password_digest", "x") ]).join
        assert_match "not a domain", GroupRule.problems([ domain("not a domain") ]).join
        assert_match "at least one", GroupRule.problems([]).join
        assert_match "at most 5", GroupRule.problems(Array.new(6) { domain("example.com") }).join
        assert_empty GroupRule.problems([ domain("example.com"), profile("locale", "en") ])
      end

      test "a rule never reads another tenant's people" do
        other = other_tenant
        within(other) { Actor.create!(nickname: "mallory", email: "mallory@example.com", email_verified_at: Time.current) }

        assert_equal %w[ada], matching([ domain("example.com") ])
      end
    end

    class GroupSourceTest < ActiveSupport::TestCase
      def make(key, **attributes)
        within { Group.create!(key: key, name: key.titleize, **attributes) }
      end

      test "a group inside itself, directly or through its parents, is refused" do
        staff = make("staff")
        make("admins", source: "group", parent_labels: [ "staff" ])

        error = assert_raises(ActiveRecord::RecordInvalid) do
          within { staff.update!(source: "group", parent_labels: [ "admins" ]) }
        end

        assert_match "inside itself", error.message

        error = assert_raises(ActiveRecord::RecordInvalid) do
          within { Group.create!(key: "loop", name: "Loop", source: "group", parent_labels: [ "loop" ]) }
        end

        assert_match "inside itself", error.message
      end

      test "a nested group names only groups that exist and labels that look like groups" do
        error = assert_raises(ActiveRecord::RecordInvalid) { make("admins", source: "group", parent_labels: [ "nobody" ]) }

        assert_match "not a group", error.message

        error = assert_raises(ActiveRecord::RecordInvalid) { make("admins", source: "group", parent_labels: [ "Not A Group!" ]) }

        assert_match "not a group key", error.message
      end

      test "a provider group needs the provider and the upstream group name" do
        error = assert_raises(ActiveRecord::RecordInvalid) { make("admins", source: "provider") }

        assert_match "Provider is needed", error.message
        assert_match "names the group at the provider", error.message
      end

      test "a source outside the four is refused" do
        error = assert_raises(ActiveRecord::RecordInvalid) { make("admins", source: "ldap") }

        assert_match "Source", error.message
      end
    end
  end
end
