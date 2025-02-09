require "test_helper"

class QueryTokenTest < GraphQLTestCase
  QUERY_TOKENS =
    "
      query ($actor: String, $device: String, $client: String) {
        tokens(actor: $actor, device: $device, client: $client) {
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
          nodes {
            id
            device {
              id
            }
            client {
              id
            }
            actor {
              id
            }
          }
        }
      }
    "
  managers_only("tokens", QUERY_TOKENS)

  paginated "tokens", QUERY_TOKENS do
    Masks::ClientToken.create!(client:)
  end

  test "tokens can be filtered by actor" do
    token = nil

    10.times { token = make_access_token }

    gql QUERY_TOKENS, actor: token.actor.identifier

    assert_equal 1, gql_result.dig("tokens", "nodes").length
    assert_equal token.actor.key,
                 gql_result["tokens"]["nodes"][0]["actor"]["id"]
  end

  test "tokens can be filtered by client" do
    token = nil

    10.times { token = make_access_token }

    gql QUERY_TOKENS, client: token.client.key

    assert_equal 1, gql_result.dig("tokens", "nodes").length
    assert_equal token.client.key,
                 gql_result["tokens"]["nodes"][0]["client"]["id"]
  end

  test "tokens can be filtered by device" do
    token = nil

    10.times { token = make_access_token }

    gql QUERY_TOKENS, device: token.device.public_id

    assert_equal 1, gql_result.dig("tokens", "nodes").length
    assert_equal token.device.public_id,
                 gql_result["tokens"]["nodes"][0]["device"]["id"]
  end
end
