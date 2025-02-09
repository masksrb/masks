require "test_helper"

class DeletionMutationTest < GraphQLTestCase
  QUERY =
    "
      mutation ($input: DeletionInput!) {
        deletion(input: $input) {
          errors
        }
      }
    "

  managers_only "deletion", QUERY, input: { type: "Device", id: "invalid" }

  test "devices can be deleted" do
    device = Masks::Device.first

    gql QUERY, input: { type: "Device", id: device.public_id }

    assert_raises ActiveRecord::RecordNotFound do
      device.reload
    end
  end

  test "tokens can be deleted" do
    token = Masks::Token.first

    gql QUERY, input: { type: "Token", id: token.key }

    assert_raises ActiveRecord::RecordNotFound do
      token.reload
    end
  end
end
