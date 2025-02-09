require "test_helper"

class ClientMutationTest < GraphQLTestCase
  QUERY =
    "
        mutation ($input: ClientInput!) {
          client(input: $input) {
            client {
              id
              name
            }

            errors
          }
        }
    "

  managers_only "client", QUERY, input: {}

  test "managers can create clients" do
    log_in "manager"

    assert_changes -> { Masks::Client.count } do
      gql QUERY,
          input: {
            name: "Testing",
            type: "internal",
            redirectUris: "http://example.com/one",
            scopes: "masks:manage",
          }
    end

    assert_equal "testing", gql_result("client", "client", "id")
    assert_equal "Testing", gql_result("client", "client", "name")
  end

  test "managers can modify existing clients" do
    log_in "manager"

    assert_no_changes -> { Masks::Client.count } do
      gql QUERY,
          input: {
            name: "Testing",
            internal: false,
            pkce: true,
            redirectUris: "http://example.com/one",
            scopes: "masks:manage",
            id: "masks",
          }
    end

    assert_equal "masks", gql_result("client", "client", "id")
    assert_equal "Testing", gql_result("client", "client", "name")
    assert_equal "Testing", manage_client.reload.name
    assert_not manage_client.reload.internal?
  end

  Masks::Client.duration_settings.each do |col|
    test "#{col} lifetime be a valid duration" do
      assert true

      log_in "manager"

      gql QUERY,
          input: {
            :id => "masks",
            col.to_s.camelize(:lower) => "invalid",
          }

      assert gql_result("client", "errors")

      gql QUERY,
          input: {
            :id => "masks",
            col.to_s.camelize(:lower) => "1 hour",
          }

      freeze_time

      assert_equal "1 hour", manage_client.reload.setting(col)
      assert_equal 1.hour.from_now, manage_client.reload.expires_at(col)
    end
  end

  test "validation errors are returned and no changes are made" do
    log_in "manager"

    gql QUERY, input: { id: "masks", type: "invalid" }

    assert manage_client.reload.internal?
    assert gql_result("client", "errors")
  end
end
