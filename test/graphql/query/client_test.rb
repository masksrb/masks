require "test_helper"

class QueryClientTest < GraphQLTestCase
  QUERY_CLIENTS =
    "
      query ($name: String, $actor: String, $device: String) {
        clients(name: $name, actor: $actor, device: $device) {
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
          nodes {
            id
          }
        }
      }
    "

  QUERY_CLIENT =
    "
      query ($id: ID!) {
        client(id: $id) {
          id
        }
      }
    "

  managers_only("clients", QUERY_CLIENTS)
  managers_only("client", QUERY_CLIENT, id: "masks")

  paginated "clients", QUERY_CLIENTS do
    make_client
  end

  test "unknown clients are not returned" do
    gql QUERY_CLIENT, id: "invalid"

    assert gql_result.key?("client")
    assert_nil gql_result["client"]
  end

  test "clients can be filtered by name" do
    3.times { make_client }

    Masks::Client.create!(name: "latest")

    gql QUERY_CLIENTS, name: "late"

    assert_equal 1, gql_result.dig("clients", "nodes").length
    assert_equal "latest", gql_result["clients"]["nodes"][0]["id"]
  end

  # test "clients can be filtered by actor (via tokens)" do
  #   3.times { make_client }

  #   gql QUERY_CLIENTS, actor: "manager"

  #   assert_equal 1, gql_result.dig("clients", "nodes").length
  #   assert_equal "masks", gql_result["clients"]["nodes"][0]["id"]
  # end

  # test "clients can be filtered by device (via entries)" do
  #   3.times { make_client }

  #   gql QUERY_CLIENTS, device: Masks::Device.last.public_id

  #   assert_equal 1, gql_result.dig("clients", "nodes").length
  #   assert_equal "masks", gql_result["clients"]["nodes"][0]["id"]
  # end
end
