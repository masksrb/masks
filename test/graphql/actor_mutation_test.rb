require "test_helper"

class ActorMutationTest < GraphQLTestCase
  QUERY =
    "
      mutation ($input: ActorInput!) {
        actor(input: $input) {
          actor {
            identifier
          }

          errors
        }
      }
    "

  managers_only "actor", QUERY, input: { identifier: "testing", signup: true }

  test "managers can create actors" do
    gql QUERY, input: { identifier: "testing", signup: true }

    assert_equal "testing", gql_result("actor", "actor", "identifier")
    assert_predicate Masks.identify("testing"), :persisted?
  end

  test "actors are only created with the signup param" do
    gql QUERY, input: { identifier: "testing" }

    assert_predicate Masks.identify("testing"), :new_record?
  end

  test "invalid emails return an error" do
    gql QUERY, input: { identifier: "&&&&@%%", signup: true }

    assert_no_changes -> { Masks::Actor.count } do
      assert_includes gql_result("actor", "errors"), "Email is invalid"
    end
  end

  test "invalid nicknames return an error" do
    gql QUERY, input: { identifier: "&&&&", signup: true }

    assert_no_changes -> { Masks::Actor.count } do
      assert_includes gql_result("actor", "errors"), "Nickname is invalid"
    end
  end

  test "passwords can be changed for any existing actor" do
    assert tester.authenticate("password")
    tester.update_attribute(:password_changed_at, nil)
    gql QUERY, input: { id: tester.key, password: "testing123" }
    assert tester.reload.authenticate("testing123")
  end

  test "passwords cannot be changed within the cooldown period" do
    assert tester.authenticate("password")
    tester.update_attribute(:password_changed_at, Time.current)
    gql QUERY, input: { id: tester.key, password: "testing123" }
    assert_includes gql_result("actor", "errors"),
                    "Password cannot be changed. Try again in 15 minutes..."
    travel_to 15.minutes.from_now + 1.second
    gql QUERY, input: { id: tester.key, password: "testing123" }
    assert_empty gql_result("actor", "errors")
    assert tester.reload.authenticate("testing123")
  end

  test "passwords can be reset within the cooldown period" do
    assert tester.authenticate("password")
    tester.update_attribute(:password_changed_at, Time.current)
    gql QUERY, input: { id: tester.key, resetPassword: true }
    assert_nil tester.reload.password_digest
  end

  test "passwords can be reset for any existing actor" do
    assert tester.authenticate("password")
    tester.update_attribute(:password_changed_at, nil)
    gql QUERY, input: { id: tester.key, resetPassword: true }
    assert_nil tester.reload.password_digest
  end

  test "backup codes can be reset for any existing actor" do
    tester.update_attribute!(:backup_codes, ["test"])
    assert tester.reload.backup_codes
    gql QUERY, input: { id: tester.key, resetBackupCodes: true }
    assert_nil tester.reload.backup_codes
  end

  test "scopes can be changed for any existing actor" do
    gql QUERY,
        input: {
          id: tester.key,
          scopes: "foobar testing baz\nbaz testing2\nbaz",
        }
    assert_equal %w[foobar testing testing2 baz openid].sort,
                 tester.reload.scopes_a
  end

  test "passwords and scopes cannot be set on signup" do
    log_in "manager"

    gql QUERY,
        input: {
          identifier: "foobar",
          password: "testing123",
          scopes: "test",
          signup: true,
        }
    assert_nil Masks.identify("foobar").password_digest
    assert_equal ["openid"], Masks.identify("foobar").scopes_a
  end
end
