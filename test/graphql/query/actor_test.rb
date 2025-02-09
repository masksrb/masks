require "test_helper"

class QueryActorTest < GraphQLTestCase
  QUERY_ACTORS =
    "
      query ($identifier: String) {
        actors(identifier: $identifier) {
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
          nodes {
            identifier
          }
        }
      }
    "

  QUERY_ACTOR =
    "
      query ($id: ID) {
        actor(id: $id) {
          identifier
        }
      }
    "

  managers_only("actors", QUERY_ACTORS)
  managers_only("actor", QUERY_ACTOR, id: "manager")

  paginated "actors", QUERY_ACTORS do
    Masks.signup("nick#{SecureRandom.alphanumeric(5)}").save!
  end

  test "unknown actors are not returned" do
    gql QUERY_ACTOR, id: "invalid"

    assert gql_result.key?("actor")
    assert_nil gql_result["actor"]
  end

  test "actors can be filtered by email" do
    assert Masks::Actor.count > 1

    gql QUERY_ACTORS, identifier: "masks@"

    assert_equal 1, gql_result.dig("actors", "nodes").length
    assert_equal "manager", gql_result["actors"]["nodes"][0]["identifier"]

    gql QUERY_ACTORS, identifier: "masks@example.com"

    assert_equal 1, gql_result.dig("actors", "nodes").length

    Masks.signup("testing123@foobar.com").save!

    gql QUERY_ACTORS, identifier: "@example.com"

    assert_equal 2, gql_result.dig("actors", "nodes").length
  end

  test "actors can be filtered by nickname" do
    assert Masks::Actor.count > 1

    gql QUERY_ACTORS, identifier: "test"

    assert_equal 1, gql_result.dig("actors", "nodes").length

    gql QUERY_ACTORS, identifier: "ma"

    assert_equal 1, gql_result.dig("actors", "nodes").length
    assert_equal "manager", gql_result["actors"]["nodes"][0]["identifier"]
  end

  test "actors can be filtered by name" do
    assert Masks::Actor.count > 1

    manager.update_attribute!(:name, "foobar")

    gql QUERY_ACTORS, identifier: "oba"

    assert_equal 1, gql_result.dig("actors", "nodes").length
    assert_equal "manager", gql_result["actors"]["nodes"][0]["identifier"]
  end
end
