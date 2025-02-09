require "test_helper"

class QuerySearchTest < GraphQLTestCase
  QUERY_SEARCH =
    "
      query ($query: String!) {
        search(query: $query) {
          actors {
            id
            identifier
          }

          clients {
            id
          }
        }
      }
    "

  managers_only("search", QUERY_SEARCH, query: "")

  setup { seed_data }

  test "actors filtered by nickname are returned" do
    gql QUERY_SEARCH, query: "nick"

    assert_equal 10, gql_result.dig("search", "actors").length
  end

  test "actors filtered by name are returned" do
    gql QUERY_SEARCH, query: "est n"

    assert_equal 10, gql_result.dig("search", "actors").length
  end

  test "actors filtered by email are returned" do
    gql QUERY_SEARCH, query: "@example.com"

    assert_equal 2, gql_result.dig("search", "actors").length
  end

  test "clients filtered by key are returned" do
    gql QUERY_SEARCH, query: "man"

    assert_equal 1, gql_result.dig("search", "clients").length
  end

  test "clients filtered by name are returned" do
    gql QUERY_SEARCH, query: "anage m"

    assert_equal 1, gql_result.dig("search", "clients").length
  end

  test "nothing is returned by default" do
    gql QUERY_SEARCH, query: ""

    assert_nil gql_result.dig("search")
  end

  private

  def seed_data
    10.times do
      Masks
        .signup("nick#{SecureRandom.alphanumeric(5)}")
        .tap do |actor|
          actor.name = "test name"
          actor.save!
        end
    end

    10.times { make_client }
  end
end
