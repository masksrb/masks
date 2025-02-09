require "test_helper"

class QueryDeviceTest < GraphQLTestCase
  QUERY_DEVICES =
    "
      query ($id: String, $actor: String) {
        devices(id: $id, actor: $actor) {
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

  QUERY_DEVICE =
    "
      query ($id: ID!) {
        device(id: $id) {
          id
        }
      }
    "

  managers_only("devices", QUERY_DEVICES)
  managers_only("device", QUERY_DEVICE) { { id: make_device.public_id } }

  paginated "devices", QUERY_DEVICES do
    make_device
  end

  test "unknown devices are not returned" do
    gql QUERY_DEVICE, id: "invalid"

    assert gql_result.key?("device")
    assert_nil gql_result["device"]
  end

  test "devices can be filtered by id" do
    3.times { make_device }

    id = Masks::Device.last.public_id

    gql QUERY_DEVICES, id: id

    assert_equal 1, gql_result.dig("devices", "nodes").length
    assert_equal id, gql_result["devices"]["nodes"][0]["id"]
  end

  test "devices can be filtered by actor (via tokens)" do
    3.times { make_device }

    gql QUERY_DEVICES, actor: "manager"

    assert_equal 1, gql_result.dig("devices", "nodes").length
  end
end
